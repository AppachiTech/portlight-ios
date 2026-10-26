# Security

Portlight holds the keys to your servers, so it's built to protect them
first and be convenient second. This page explains what it protects, how,
and where the limits are.

## What Portlight protects against

| Threat | Protection |
| --- | --- |
| Someone picks up your unlocked phone | The app always opens with Face ID, Touch ID or the passcode, and re-locks when it leaves the foreground. A grace period of at most five minutes is optional; the default is immediate. It's timed on a monotonic clock, so changing the date and time can't stretch it. |
| A phone with no passcode | Portlight refuses to open. Keychain items are bound to "passcode set", so iOS deletes them if the passcode is removed. |
| An attacker who gets past the app's lock screen | Secrets are Keychain items with **user presence** access control. iOS itself releases them only to a context that passed device-owner authentication, so bypassing the app's UI isn't enough. |
| Theft of a backup, or a new phone restored from one | Keychain items are `ThisDeviceOnly`: never synced to iCloud, never in backups. App data files are excluded from backups and use complete file protection, so they're unreadable while the phone is locked. |
| Secrets left behind after deleting the app | iOS keeps Keychain items when an app is deleted. On the first launch of a fresh install, Portlight removes any it left behind. |
| Extracting a private key from the phone | Secure Enclave keys are generated inside the chip and can't leave it. Portlight stores only an opaque, device-bound handle. Signing needs user presence, which is the Face ID, Touch ID or passcode check that unlocked Portlight: it covers every signature until the app locks again, rather than prompting for each one. |
| Man-in-the-middle / impostor server | Host keys are trust-on-first-use with the SHA-256 fingerprint shown. A changed key stops the connection and shows both fingerprints, including a key of a different type than the one trusted. Replacing it takes two deliberate taps. Revoked keys (`@revoked` in an imported known_hosts, even for a key already trusted) are refused without asking. No password or key is sent before the host key is accepted, and every jump host is checked under its own name. |
| A keylogging keyboard | Third-party keyboard extensions are refused app-wide, so keystrokes, including passwords at `sudo` prompts, never pass through one. |
| Clipboard leaks | Text copied from a terminal, and text a server sets via OSC 52, is local-only (no Universal Clipboard) and expires after two minutes. Servers can never read your clipboard. |
| Pasting something that runs commands | Pastes and typed saved commands are cleaned of control characters, so an embedded ESC can't end a bracketed paste early and run what follows. Without bracketed paste, several lines (including Windows `\r\n` line endings) ask first and show the lines. |
| A hostile server's output | Output passes through a filter before the terminal emulator: kitty graphics (which could probe files in the app) are dropped, over-long escape strings are capped, and title-stack floods are ignored. When the terminal falls behind, Portlight stops reading so the server pauses, instead of buffering until the app runs out of memory. |
| Secrets in saved commands | Saved commands and a host's Run on connect command are plain text, so the editor refuses ones that look like they hold a password, key or token (AWS keys, GitHub and other API tokens, JWTs, private keys, passwords in URLs or options), and flags any saved before the check. Host notes get a warning. References like `$TOKEN` are fine. |
| Voice input running something, or leaking | Inserted speech never presses Return: line breaks become spaces and control characters are dropped. Speech is recognised on the device only; where that isn't available Portlight says so rather than sending audio to Apple's servers. The microphone is only on between Speak and Stop, and stops when the app leaves the foreground. |
| Malicious links in output | Only `http` and `https` links open, never other URL schemes, and only after Portlight shows the real address: a link's text can differ from where it points. |
| Shoulder-surfing in the app switcher | A privacy cover, in its own window above the terminal and every sheet, replaces the app's snapshot whenever it isn't active. |
| Hostile key files | Imported key files are bounds-checked, may ask for at most 1,000 bcrypt rounds, and are decrypted off the main thread. A private key pasted in is cleared from the clipboard after import. |
| Tampered release builds | Release IPAs are built from the committed lockfile with pinned tools, and carry a GitHub build provenance attestation as well as a checksum. |
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
- **Keep screen awake.** With this setting on, the screen doesn't dim
  while a terminal is open, so the phone never locks itself and the app
  lock isn't reached. Turn it off, or lock the phone yourself, when you
  leave it.
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
