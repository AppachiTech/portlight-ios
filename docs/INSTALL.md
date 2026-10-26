# Installing Portlight

Portlight isn't on the App Store, and there are no plans to publish it there
for now. iOS only runs apps signed for your device, so there are three ways
to get it on your phone. New to this? [GETTING_STARTED.md](../GETTING_STARTED.md)
walks through the first one step by step.

## 1. Build it yourself (recommended)

This is the most transparent route: you run exactly the code you can read.
Follow [BUILDING.md](BUILDING.md). It takes about ten minutes the first time.

| Apple ID | How long a build keeps working |
| --- | --- |
| Free | 7 days, then press Run in Xcode again |
| Paid developer account | 1 year |

## 2. Sign a release build

Tagged releases on GitHub include an **unsigned** `Portlight.ipa` built by
CI, plus its SHA-256 checksum and a build provenance attestation. Before
installing:

1. Check the checksum: `shasum -a 256 Portlight.ipa` must match
   `Portlight.ipa.sha256`.
2. Check it was built by this repository's release workflow, with the
   [GitHub CLI](https://cli.github.com): `gh attestation verify Portlight.ipa --repo AppachiTech/portlight-ios`.
   The checksum only catches a damaged download; the attestation shows
   the file came from the workflow, unchanged.
3. Sign and install it with your own Apple ID using an open-source
   sideloading tool such as [SideStore](https://sidestore.io) or
   [AltStore](https://altstore.io).

The same 7-day limit applies with a free Apple ID.

## 3. Private over-the-air install (paid account)

For your own devices, you can host a signed build on any HTTPS server, such
as a Cloudflare R2 bucket with a custom domain, and install it from Safari.
No cable or Xcode is needed after the first setup.

1. In the Apple Developer portal, register each iPhone's UDID. The UDID is
   shown in Finder when the phone is connected, or in Xcode under
   **Window → Devices and Simulators**.
2. In Xcode, use **Product → Archive**, then **Distribute App → Release
   Testing** (ad hoc). Export the `.ipa`.
3. Make the install files:

   ```sh
   make ota URL=https://downloads.example.com/portlight IPA=path/to/Portlight.ipa
   ```

   This writes `build/ota/` with `index.html`, `manifest.plist` and the
   `.ipa`. The URL must be HTTPS.
4. Upload the contents of `build/ota/` to that URL. With R2, for example:

   ```sh
   # In your R2 bucket's settings, connect a custom domain first.
   rclone copy build/ota r2:your-bucket/portlight
   ```

5. On the iPhone, open `https://downloads.example.com/portlight/index.html`
   in Safari and tap **Install**.

Only devices whose UDIDs are in the build's provisioning profile can
install it. The install page shows the package's SHA-256 so you can check
it matches what you built. Don't make the bucket listable, and treat the
link as private: it's your personal build.

## After installing

Portlight asks for Face ID, Touch ID or your passcode the first time it
opens, and every time after that. If your phone has no passcode, set one
first. Portlight won't open without it.

Then see [USING.md](USING.md) to add your first server.
