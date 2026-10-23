#!/usr/bin/env python3
"""Writes the files for a private over-the-air install of a SIGNED
Portlight.ipa (ad hoc or development signed, with your device's UDID in
the provisioning profile; this needs a paid Apple developer account).

Upload the output folder to any HTTPS host you control, for example a
Cloudflare R2 bucket with a custom domain, then open index.html on the
iPhone in Safari and tap Install. iOS refuses OTA installs over plain
HTTP. See docs/INSTALL.md.
"""
import argparse
import hashlib
import html
import pathlib
import plistlib
import shutil
import subprocess
import zipfile


def bundle_info(ipa: pathlib.Path) -> dict:
    with zipfile.ZipFile(ipa) as z:
        name = next(n for n in z.namelist() if n.startswith("Payload/") and n.endswith(".app/Info.plist")
                    and n.count("/") == 2)
        return plistlib.loads(z.read(name))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", required=True, help="HTTPS URL the output folder will be served from")
    parser.add_argument("--ipa", required=True, type=pathlib.Path, help="a signed Portlight.ipa")
    parser.add_argument("--out", default="build/ota", type=pathlib.Path)
    args = parser.parse_args()

    base = args.base_url.rstrip("/")
    if not base.startswith("https://"):
        parser.error("--base-url must be https:// (iOS refuses OTA installs over HTTP)")
    info = bundle_info(args.ipa)
    bundle_id = info["CFBundleIdentifier"]
    version = info.get("CFBundleShortVersionString", "0")
    build = info.get("CFBundleVersion", "0")

    args.out.mkdir(parents=True, exist_ok=True)
    ipa_name = f"Portlight-{version}-{build}.ipa"
    shutil.copyfile(args.ipa, args.out / ipa_name)
    digest = hashlib.sha256((args.out / ipa_name).read_bytes()).hexdigest()

    manifest = {
        "items": [{
            "assets": [{"kind": "software-package", "url": f"{base}/{ipa_name}"}],
            "metadata": {
                "bundle-identifier": bundle_id,
                "bundle-version": version,
                "kind": "software",
                "title": "Portlight",
            },
        }]
    }
    (args.out / "manifest.plist").write_bytes(plistlib.dumps(manifest))
    install = f"itms-services://?action=download-manifest&url={base}/manifest.plist"
    (args.out / "index.html").write_text(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Install Portlight</title>
<style>
body {{ font: 17px -apple-system, system-ui, sans-serif; background: #101418; color: #e8e6e3;
       display: grid; place-items: center; min-height: 100vh; margin: 0; padding: 16px; box-sizing: border-box; }}
main {{ max-width: 420px; text-align: center; }}
a.button {{ display: inline-block; background: #f5a524; color: #101418; font-weight: 600;
           padding: 14px 28px; border-radius: 12px; text-decoration: none; margin: 16px 0; }}
code {{ font-size: 12px; word-break: break-all; color: #9aa4ad; }}
</style></head><body><main>
<h1>Portlight {html.escape(version)} ({html.escape(build)})</h1>
<p>Open this page in Safari on the iPhone whose UDID is in the build's provisioning profile.</p>
<a class="button" href="{html.escape(install)}">Install</a>
<p><small>SHA-256 of the app package:</small><br><code>{digest}</code></p>
</main></body></html>
""")
    print(f"Wrote {args.out}/ (index.html, manifest.plist, {ipa_name})")
    print(f"Upload the folder to {base}/ and open {base}/index.html on the iPhone.")
    if shutil.which("plutil"):
        subprocess.run(["plutil", "-lint", str(args.out / "manifest.plist")], check=False)


if __name__ == "__main__":
    main()
