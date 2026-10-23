# Security

Portlight holds the keys to your servers, so it's built to protect them
first and be convenient second. This page explains what it protects, how,
and where the limits are.

## What Portlight protects against

| Threat | Protection |
| --- | --- |
| Someone picks up your unlocked phone | The app always opens with Face ID, Touch ID or the passcode, and re-locks when it leaves the foreground. A grace period of at most five minutes is optional; the default is immediate. |
| A phone with no passcode | Portlight refuses to open. Keychain items are bound to "passcode set", so iOS deletes them if the passcode is removed. |
| An attacker who gets past the app's lock screen | Secrets are Keychain items with **user presence** access control. iOS itself releases them only to a context that passed device-owner authentication, so bypassing the app's UI isn't enough. |
| Theft of a backup, or a new phone restored from one | Keychain items are `ThisDeviceOnly`: never synced to iCloud, never in backups. App data files are excluded from backups and use complete file protection, so they're unreadable while the phone is locked. |
| Extracting a private key from the phone | Secure Enclave keys are generated inside the chip and can't leave it. Portlight stores only an opaque, device-bound handle, and each signature needs user presence. |
| Man-in-the-middle / impostor server | Host keys are trust-on-first-use with the SHA-256 fingerprint shown. A changed key stops the connection and shows both fingerprints. Replacing it takes two deliberate taps. Revoked keys (`@revoked` in an imported known_hosts) are refused without asking. |
| A keylogging keyboard | Third-party keyboard extensions are refused app-wide, so keystrokes, including passwords at `sudo` prompts, never pass through one. |
| Clipboard leaks | Text copied from a terminal, and text a server sets via OSC 52, is local-only (no Universal Clipboard) and expires after two minutes. Servers can never read your clipboard. |
| Pasting something that runs commands | A multi-line paste into a shell without bracketed-paste mode asks first and shows the lines. |
| Malicious links in output | Only `http` and `https` links open, never other URL schemes. |
| Shoulder-surfing in the app switcher | A privacy cover replaces the app's snapshot whenever it isn't active. |
| Exported keys | Private key exports are always encrypted (OpenSSH format, aes256-ctr with bcrypt-pbkdf, 16 rounds). The passphrase must be at least 8 characters. Secure Enclave keys can't be exported at all. |
| Tracking | There are no accounts, analytics, crash reporters or third-party SDKs. The only network connections are the SSH connections you start. |

## Cryptography

Portlight doesn't implement the SSH protocol itself. It uses Apple's
[SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) directly, not a fork.

| Area | What's used |
| --- | --- |
| Key exchange | curve25519-sha256, ecdh-sha2-nistp256/384/521 |
| Ciphers | aes128-gcm@openssh.com, aes256-gcm@openssh.com |
| Host keys accepted | ssh-ed25519, ecdsa-sha2-nistp256/384/521 |
| User keys | Ed25519, ECDSA P-256/384/521, Secure Enclave P-256 |
| Key files | openssh-key-v1: read none, aes-ctr, aes-cbc and aes-gcm; write aes256-ctr. bcrypt-pbkdf is implemented in Portlight and tested against an independent implementation and real `ssh-keygen` files. |
| Primitives | [swift-crypto](https://github.com/apple/swift-crypto) (CryptoKit on Apple platforms) |

## Known limits

- **No RSA keys.** SwiftNIO SSH doesn't support RSA user keys or RSA host
  keys. Generate an Ed25519 key in Portlight and add its public key to the
  server. On AWS you can also create an ED25519 key pair. A server that
  offers only an RSA host key can't be reached; every mainstream cloud
  image also has an Ed25519 key.
- **No keyboard-interactive authentication**, so no OTP prompts. Public
  key and password logins work.
- **Strings in memory.** Swift can't reliably wipe memory, so a password
  you type exists in the app's memory while it's used. Keys on the
  Secure Enclave never enter app memory.
- **Background connections.** iOS suspends apps in the background, and
  connections usually drop after a short while. Use `tmux` or `screen` on
  the server so work survives. Portlight shows a Reconnect button.
- **Trust on first use.** The first connection to a server trusts what you
  approve. Compare the fingerprint with the server's, using
  `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` or the cloud console's
  boot log, before tapping Trust.
- **The app code has not had an external audit.**

## Reporting a vulnerability

Please report security problems privately, using GitHub's **Security → Report a vulnerability** on this repository, rather than
a public issue. Include steps to reproduce. We'll acknowledge reports
and credit you in the fix unless you prefer otherwise.
