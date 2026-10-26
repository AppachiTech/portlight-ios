# Building Portlight

## What you need

- A Mac with **Xcode 16 or later**.
- **XcodeGen**, to create the Xcode project from `project.yml`:
  `brew install xcodegen`.
- An **Apple ID**. A free one works for your own phone. A paid developer
  account ($99/year) gives longer-lived installs and over-the-air installs.
- An iPhone or iPad on **iOS 17 or later**.

## First build

```sh
git clone https://github.com/MadhuAppachi/portlight.git portlight
cd portlight-ios
make open
```

`make open` runs `xcodegen generate` and opens `Portlight.xcodeproj`. Xcode
then downloads the Swift packages. The project file isn't committed;
regenerate it whenever `project.yml` changes.

The first build may stop twice for one-time Xcode prompts:

- **"Plugin SwiftTermBuildInfoPlugin must be enabled".** Click the error
  and choose **Trust & Enable**. SwiftTerm uses this small build plugin.
- **"The Metal Toolchain was not installed".** SwiftTerm includes Metal
  shaders, and recent Xcode versions download the Metal compiler
  separately: **Xcode → Settings → Components → Metal Toolchain → Get**, or
  `xcodebuild -downloadComponent MetalToolchain`. It's about 800 MB.

### Signing

1. In Xcode, open **Settings → Accounts** and add your Apple ID. That
   creates a "Personal Team" if you don't have a paid account.
2. Copy the signing template and fill it in:

   ```sh
   cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
   ```

   Set `DEVELOPMENT_TEAM` to your team ID, shown next to your account in
   Xcode Settings. Set `PORTLIGHT_BUNDLE_ID` to something unique to you, such
   as `com.yourname.portlight`. This file is git-ignored.
3. Run `make project` again. Your settings are included automatically.

You can instead pick the team in Xcode under **Portlight target → Signing &
Capabilities**. That change is lost the next time the project is generated.

### Running on your phone

1. Connect the iPhone by cable, or over Wi-Fi once paired.
2. On the iPhone, turn on **Settings → Privacy & Security → Developer
   Mode** and restart when asked.
3. In Xcode, choose your iPhone as the run destination and press **Run**.
4. The first time, iOS asks you to trust the developer. Go to
   **Settings → General → VPN & Device Management**, pick your Apple ID and
   tap Trust.

With a free Apple ID the app stops opening after **7 days**. Press Run
again to renew it. A paid account makes builds last a year.

## Tests

The core package builds and tests on macOS and Linux:

```sh
make test
```

The SSH integration tests start a temporary `sshd` on 127.0.0.1, as your
own user, with its own config and keys in a temporary directory. They need
OpenSSH's `sshd` and `ssh-keygen`. Set `PORTLIGHT_SKIP_SSHD=1` to skip them.

In Xcode, **Product → Test** runs the core unit tests (the `PortlightKitTests`
target).

## Troubleshooting

- **"No account for team" or signing errors.** Check
  `Config/Signing.local.xcconfig`, then run `make project` again.
- **"Failed to register bundle identifier".** The bundle ID is taken. Pick
  another `PORTLIGHT_BUNDLE_ID`.
- **Package resolution fails.** Use **File → Packages → Reset Package
  Caches**, then build again.
- **"xcodebuild requires Xcode, but active developer directory … is a
  command line tools instance".** Point the tools at Xcode:
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- **"You have not agreed to the Xcode license agreements".** Run
  `sudo xcodebuild -license accept`.
- **The Metal Toolchain download sits at "Preparing to download".** Quit
  Xcode, run `sudo killall mobileassetd` (the service that downloads
  components), and try again. If it's still stuck, restart the Mac.
- **"Untrusted Developer" on the phone.** Go to **Settings → General → VPN
  & Device Management**, pick your Apple ID and tap Trust.
- **Something else.** Open an issue with the error text, or fix it and
  send a pull request.

## Regenerating generated files

| Command | Regenerates |
| --- | --- |
| `make icon` | `App/Portlight/Assets.xcassets/AppIcon.appiconset/AppIcon.png` |
| `make fixtures` | `PortlightCore/Tests/PortlightKitTests/KeyFixtures.swift` (needs `ssh-keygen` and `openssl`) |
| `scripts/gen_blowfish_constants.py` | Blowfish constants, computed from the digits of pi |
