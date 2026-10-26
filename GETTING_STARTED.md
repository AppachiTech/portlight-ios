# Getting started with Portlight

This guide takes you from nothing to a working SSH session on your iPhone or
iPad: building the app, putting it on your phone, connecting your first
server, and keeping it running. It takes about 30 minutes the first time.

> [!IMPORTANT]
> **Portlight isn't on the App Store.** You build it yourself from this
> repository and install it on your own devices. With a free Apple ID, iOS
> stops the app opening **7 days** after you install it, and you rebuild to
> keep using it (see [Keeping it running](#6-keeping-it-running)). There are
> no plans to publish to the App Store right now. That may change later.

## Contents

1. [What you need](#1-what-you-need)
2. [Build the app](#2-build-the-app)
3. [Put it on your phone](#3-put-it-on-your-phone)
4. [Connect your first server](#4-connect-your-first-server)
5. [Everyday use](#5-everyday-use)
6. [Keeping it running](#6-keeping-it-running)
7. [Trying it without a server](#7-trying-it-without-a-server)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. What you need

| | |
| --- | --- |
| A Mac | With **Xcode 26 or later** from the Mac App Store, new enough for the iOS version on your phone. |
| An iPhone or iPad | On **iOS 17 or later**, with a passcode set. Portlight won't open without one. |
| An Apple ID | A **free** one works. A paid developer account ($99 a year) makes installs last a year instead of 7 days. |
| A cable | For the first install. Later installs can go over Wi-Fi. |
| Homebrew | To install XcodeGen: [brew.sh](https://brew.sh). |

## 2. Build the app

### 2.1 Get the code and the tools

```sh
brew install xcodegen
git clone https://github.com/AppachiTech/portlight-ios.git
cd portlight-ios
```

If Xcode has never run on this Mac, open it once and let it install its
components. If the terminal says `xcodebuild` "requires Xcode", point the
command-line tools at Xcode and accept its license:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

### 2.2 Set up signing

iOS only runs apps signed for your devices, so the app is signed with your
own Apple ID.

1. Open Xcode, then **Xcode → Settings → Accounts**, click **+** and add
   your Apple ID. With a free account this creates a "Personal Team".
2. Copy the signing template:

   ```sh
   cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
   ```

3. Open `Config/Signing.local.xcconfig` and set two values:

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   PORTLIGHT_BUNDLE_ID = com.yourname.portlight
   ```

   - **`DEVELOPMENT_TEAM`** is your 10-character Team ID. To find it, run
     `make open` (next step), select the **Portlight** target, open
     **Signing & Capabilities**, choose your team, then run
     `grep -m1 DEVELOPMENT_TEAM Portlight.xcodeproj/project.pbxproj`.
   - **`PORTLIGHT_BUNDLE_ID`** must be unique to you. Use your own name or
     domain. If Xcode says the identifier "is not available", pick another.

   This file is ignored by git, so your details never end up in a commit.

### 2.3 Generate the project and open it

```sh
make open
```

This creates `Portlight.xcodeproj` from `project.yml` and opens it. Xcode
then downloads the Swift packages. Run `make open` again whenever you
change the signing file or `project.yml`.

### 2.4 One-time Xcode prompts

The first build may stop twice. Both are normal:

- **"Plugin SwiftTermBuildInfoPlugin must be enabled".** Click the error
  in the Issue navigator and choose **Trust & Enable**.
- **"The Metal Toolchain was not installed".** Install it from
  **Xcode → Settings → Components**, or with
  `xcodebuild -downloadComponent MetalToolchain` (about 800 MB).

## 3. Put it on your phone

1. Connect the iPhone with a cable, unlock it, and tap **Trust This
   Computer**.
2. On the iPhone, turn on **Settings → Privacy & Security → Developer
   Mode**. The phone restarts; confirm **Turn On** afterwards. If the
   switch isn't there yet, it appears once Xcode has seen the phone.
3. In Xcode, choose your iPhone in the device menu at the top and press
   **Run** (⌘R).
4. The first launch is blocked as "Untrusted Developer". On the iPhone, go
   to **Settings → General → VPN & Device Management**, tap your Apple ID
   under **Developer App**, and tap **Trust**.
5. Open **Portlight**. It asks for Face ID, Touch ID or your passcode. It
   always does, every time it opens.

> [!TIP]
> In Xcode, **Window → Devices and Simulators**, select your phone and tick
> **Connect via network**. Later installs then work over Wi-Fi.

## 4. Connect your first server

The safest setup is a key made on the phone. Its private half never leaves
the device.

1. **Make a key.** **Keys → + → New Ed25519 key**. For a key that can never
   leave the phone at all, choose **New Secure Enclave key**.
2. **Put the public key on the server.** Open the key and tap **Copy**. With
   Universal Clipboard it's on your Mac too. Then, from a machine that can
   already log in to the server:

   ```sh
   echo 'ssh-ed25519 AAAA… iPhone' >> ~/.ssh/authorized_keys
   ```

   For AWS, Google Cloud and Azure specifics, see
   [docs/USING.md](docs/USING.md#putting-the-key-on-a-server).
3. **Add the host.** **Hosts → +**. Enter the hostname or IP, the port
   (usually 22) and the username, and set **Log in with** to your key. Pick
   the provider to get its usual usernames (`ec2-user`, `ubuntu`,
   `azureuser`…).
4. **Connect and check the fingerprint.** Tap the host. The first time,
   Portlight shows the server's key fingerprint. Compare it with the
   server's own:

   ```sh
   ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
   ```

   If they match, tap **Trust and connect**. If a known server's key ever
   changes, Portlight stops and warns you in red.

Already use SSH on a computer? **Settings → Import ~/.ssh/config** brings
in your hosts, and **Settings → Trusted host keys → Import** brings in
`known_hosts`. Password logins work too, but keys are safer.

## 5. Everyday use

The full guide is [docs/USING.md](docs/USING.md). The essentials:

- **Key bar.** Above the keyboard: Esc, sticky Ctrl and Alt (tap twice to
  lock), Tab, arrows, symbols, F-keys and **{ }** for saved commands. The
  button at its left edge hides the keyboard.
- **Text size and rotation.** **A−** and **A+** in the tab bar, or pinch.
  The rotate button turns the terminal to landscape, even with rotation
  lock on. **⋯ → Fit 80 columns** stops long lines wrapping.
- **Speak to type.** With the keyboard down, a strip under the terminal
  takes speech. Tap **Speak**, talk, tap **Stop**, edit the draft if you
  need to, then **Insert**. Insert never presses Return; **⏎** does. Speech
  is recognised on the phone and audio never leaves it. It's made for
  telling tools like Claude Code what to do.
- **Saved commands.** `git status`, `terraform plan` and your own, from
  **{ }** or the voice strip. They're typed without running, so you check
  them, then press ⏎. Portlight won't save one that contains a password or
  token.
- **Tabs.** Keep several sessions open; **⌄** goes back to your hosts.
- **Dropped connections.** iOS suspends apps in the background, so
  sessions drop after a while. Run `tmux new -A -s main` on the server (or
  set it as the host's **Run on connect**) and your work survives. Tap
  **Reconnect** to pick it back up.

## 6. Keeping it running

| Apple ID | How long an install works |
| --- | --- |
| Free | **7 days** |
| Paid developer account | 1 year |

When it expires, the app stays on the phone but won't open. To renew it,
connect the phone (by cable, or over Wi-Fi if you set that up), open the
project and press **Run** again. Installing over the existing app keeps
your hosts, keys and settings.

Updating is the same: pull the latest code, run `make open`, and press
**Run**.

```sh
git pull
make open
```

Free accounts have a few more limits from Apple: at most 3 apps installed
this way at a time, and a limited number of new bundle identifiers per
week. Keep the same `PORTLIGHT_BUNDLE_ID` and you won't run into them.

> [!NOTE]
> **Why not the App Store?** Portlight is built and maintained in the open,
> and for now it's meant for people comfortable building it themselves.
> There are no plans to publish it to the App Store at the moment. That may
> change in the future. Watch the repository to hear about it.

There are other ways to install, including signing a release build with
AltStore or SideStore, or an over-the-air install with a paid account: see
[docs/INSTALL.md](docs/INSTALL.md).

## 7. Trying it without a server

`demo/server/` has a throwaway SSH server that runs in Docker on your Mac:
a made-up host called `atlas` with a sample project, reachable from your
phone on the same Wi-Fi. It's handy for trying Portlight, and for
screenshots that don't show a real server.

```sh
demo/server/demo-server.sh up                            # start it; prints host, port and fingerprints
demo/server/demo-server.sh key 'ssh-ed25519 AAAA… iPhone'   # allow your Portlight key
demo/server/demo-server.sh down                          # stop it
```

Details are in [demo/server/README.md](demo/server/README.md).

## 8. Troubleshooting

| Problem | Fix |
| --- | --- |
| `xcodebuild` "requires Xcode, but active developer directory … is a command line tools instance" | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| "You have not agreed to the Xcode license agreements" | `sudo xcodebuild -license accept` |
| "… is using Swift tools version … but the installed version is …" | Xcode is too old for Portlight's packages. Update to Xcode 26 or later. |
| "No account for team", or other signing errors | Check `Config/Signing.local.xcconfig`, then run `make open` again. |
| "Failed to register bundle identifier" | Someone already uses it. Change `PORTLIGHT_BUNDLE_ID`. |
| "Communication with Apple failed: your team has no devices" | Connect the phone and select it as the run destination; the warning clears. |
| Metal Toolchain download stuck at "Preparing to download" | Quit Xcode, run `sudo killall mobileassetd`, and try again. If it's still stuck, restart the Mac. |
| "Untrusted Developer" on the phone | **Settings → General → VPN & Device Management** → your Apple ID → **Trust**. |
| The app won't open after a week | The free install expired: press **Run** in Xcode again. |
| Portlight says the phone has no passcode | Set one in **Settings → Face ID & Passcode**. Portlight requires it. |
| RSA key won't import | Not supported yet. Make an Ed25519 key in Portlight instead. |

Still stuck? [Open an issue](https://github.com/AppachiTech/portlight-ios/issues)
with the error text. For security problems, use **Security → Report a
vulnerability** instead. More detail on building is in
[docs/BUILDING.md](docs/BUILDING.md).
