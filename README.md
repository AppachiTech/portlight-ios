# Portlight

An open-source SSH terminal for iPhone and iPad, made for reaching cloud
servers (AWS, Google Cloud, Azure, DigitalOcean, or anything that speaks SSH)
from your phone. It's an SSH client only: your tools, including the aws and
gcloud CLIs, run on the servers you connect to.

Portlight isn't on the App Store. You build it yourself from this repository,
or install a build you signed. See [docs/INSTALL.md](docs/INSTALL.md).

## Features

- **A real terminal.** xterm-256color, via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
  vim, tmux, htop and friends work. Portrait and landscape (forced from the
  tab bar, even with rotation lock on), A−/A+ and pinch to zoom, fit 80
  columns, seven themes.
- **Speak to type.** In landscape the keyboard stays down and a voice panel
  takes its place. Speech lands in a draft you can edit, then Insert types
  it without pressing Return. Recognised on the phone; audio never leaves it.
- **Keys the phone lacks.** A scrolling bar above the keyboard has Esc,
  sticky Ctrl and Alt (tap twice to lock), Tab, arrows that auto-repeat,
  shell symbols, F1–F12 and saved snippets.
- **Tabs.** Keep several sessions open. Each tab's screen survives switching
  apps and locking.
- **Keys, not passwords.** Generate Ed25519 or ECDSA keys, or a Secure
  Enclave key that can never leave the phone. Import existing OpenSSH or PEM
  keys, including passphrase-protected ones.
- **Jump hosts.** Reach private instances through a bastion, like ProxyJump.
- **Bring your setup.** Import `~/.ssh/config` and `known_hosts`. Quick
  connect from `user@host:port` or a pasted `ssh` command.
- **Cloud-aware details.** Per-provider default usernames (`ec2-user`,
  `ubuntu`, `azureuser`…) and the right public-key line for each provider,
  including GCP's username-as-comment format.

## Security

Portlight always opens with Face ID, Touch ID or your passcode, and it
won't run on a phone without a passcode. Passwords and keys live in the
Keychain on this device only, and iOS itself withholds them until you
authenticate. Host keys are checked on every connection. Third-party
keyboards are blocked, terminal copies expire, and servers can't read your
clipboard. There are no accounts, analytics or tracking.

Details and limits are in [docs/SECURITY.md](docs/SECURITY.md).

## Build it

You need a Mac with Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
make open          # generates Portlight.xcodeproj and opens it
```

Pick your iPhone and press Run. Signing setup is in [docs/BUILDING.md](docs/BUILDING.md).

## Layout

| Path | What's there |
| --- | --- |
| `PortlightCore/` | Swift package: everything except the UI. Builds and tests on Linux and macOS. |
| `PortlightCore/Sources/PortlightKit` | Keys and key files, hosts, `~/.ssh/config` import, known hosts, key encoding, themes, settings, the library store. |
| `PortlightCore/Sources/PortlightSSH` | SSH connections on Apple's SwiftNIO SSH: shells, PTYs, jump hosts, sessions. |
| `App/Portlight` | The SwiftUI app. |
| `project.yml` | XcodeGen spec for the Xcode project. |
| `scripts/` | Icon, test fixtures, IPA and over-the-air install helpers. |
| `docs/` | Building, installing, security, architecture, user guide. |

## Tests

```sh
make test   # = cd PortlightCore && swift test
```

The tests cover key formats against real `ssh-keygen` and `openssl` output,
bcrypt-pbkdf against an independent implementation, config and known-hosts
parsing, and terminal key encoding. They also run end-to-end SSH against a
throwaway OpenSSH server on 127.0.0.1: every key type, host key checks,
PTY size and resize, Ctrl-C, jump hosts and session handling. Those
server tests run when `sshd` is installed, and are skipped otherwise.

## License

MIT. See [LICENSE](LICENSE). Portlight builds on SwiftNIO SSH, SwiftNIO and
swift-crypto (Apache 2.0, Apple) and SwiftTerm (MIT, Miguel de Icaza).
