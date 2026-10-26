# Portlight

[![CI](https://github.com/AppachiTech/portlight-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/AppachiTech/portlight-ios/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An open-source SSH terminal for iPhone and iPad, made for reaching cloud
servers (AWS, Google Cloud, Azure, DigitalOcean, or anything that speaks SSH)
from your phone. It's an SSH client only: your tools, including the aws and
gcloud CLIs, run on the servers you connect to.

Portlight isn't on the App Store, and there are no plans to publish it there
for now (that may change later). You build it yourself from this repository
and install it on your own devices. **Start with [GETTING_STARTED.md](GETTING_STARTED.md):**
it covers everything from building to your first connection.

> **Heads-up:** with a free Apple ID, iOS stops a self-built app opening after
> **7 days**; press Run in Xcode again to renew it. A paid developer account
> makes installs last a year.

> **Status:** early and actively developed. The core SSH and crypto code is
> well tested, but Portlight hasn't had an external security audit. Read
> [docs/SECURITY.md](docs/SECURITY.md) for what it protects and its limits.

## Features

- **A real terminal.** xterm-256color, via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
  vim, tmux, htop and friends work. Portrait and landscape (forced from the
  tab bar, even with rotation lock on), A−/A+ and pinch to zoom, fit 80
  columns, seven themes.
- **Speak to type.** A strip under the terminal takes speech, in portrait or
  landscape. It lands in a draft you can edit, then Insert types it without
  pressing Return. Recognised on the phone; audio never leaves it.
- **Saved commands.** `git status`, `terraform plan` and your own, one tap
  away. Portlight refuses to save ones that contain a password or token.
- **Keys the phone lacks.** A scrolling bar above the keyboard has Esc,
  sticky Ctrl and Alt (tap twice to lock), Tab, arrows that auto-repeat,
  shell symbols, F1–F12 and saved commands.
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

Details and limits are in [docs/SECURITY.md](docs/SECURITY.md). To report a
vulnerability, use **Security → Report a vulnerability** on GitHub rather
than a public issue.

## Build it

You need a Mac with Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen),
and an iPhone or iPad on iOS 17 or later. A free Apple ID is enough.

```sh
git clone https://github.com/AppachiTech/portlight-ios.git
cd portlight-ios
brew install xcodegen
make open          # generates Portlight.xcodeproj and opens it
```

Set up signing first, then pick your iPhone and press Run. The full
walkthrough, including signing and the one-time Xcode prompts, is in
[GETTING_STARTED.md](GETTING_STARTED.md).

## Documentation

| Guide | For |
| --- | --- |
| [GETTING_STARTED.md](GETTING_STARTED.md) | **Start here:** build, install, connect your first server, keep it running |
| [docs/BUILDING.md](docs/BUILDING.md) | Building, signing, running on your phone, troubleshooting |
| [docs/INSTALL.md](docs/INSTALL.md) | Other ways to install, including signing a release build |
| [docs/USING.md](docs/USING.md) | Adding servers, keys, the terminal, voice input, saved commands |
| [docs/SECURITY.md](docs/SECURITY.md) | What Portlight protects against, and its limits |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the code fits together |

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

## Contributing

Bug reports, ideas and pull requests are welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md), and please follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

MIT. See [LICENSE](LICENSE). Portlight builds on SwiftNIO SSH, SwiftNIO and
Swift Crypto (Apache 2.0, Apple) and SwiftTerm (MIT, Miguel de Icaza); the
full list is in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
