# Architecture

```
App/Portlight (SwiftUI, UIKit, SwiftTerm)        iOS only
        │
        ▼
PortlightSSH  ── SSHConnection, SSHShell, TerminalSession, SessionManager
        │       (Apple's SwiftNIO SSH)
        ▼
PortlightKit  ── keys and key files, hosts, known hosts, ssh_config,
                key encoding, themes, settings, Library
                (swift-crypto)
```

Everything below the app is in the `PortlightCore` Swift package. It
compiles and is tested on Linux as well as Apple platforms, which keeps
the protocol and crypto code testable without a phone.

## PortlightKit

- **Keys.** `SSHPrivateKey` (Ed25519, ECDSA), `SSHPublicKey` (wire blobs,
  `authorized_keys` lines, SHA-256 fingerprints), `OpenSSHKeyFile`
  (openssh-key-v1 read and write), `BcryptPBKDF` with its own Blowfish,
  `KeyImporter` (format detection and clear errors), `KeyRecord`.
- **Hosts.** `SSHHost`, `CloudProvider` presets, `QuickConnect`,
  `SSHConfigParser`.
- **Security.** `KnownHosts` (trust on first use, OpenSSH import and
  export, hashed names, pattern lists) and `AppLockPolicy` (timed on a
  monotonic clock).
- **Terminal.** `KeyEncoder` (xterm sequences for the key bar),
  `StickyModifiers`, `TerminalTheme`, `AppSettings`, `Snippet` (saved
  commands). Three filters guard what crosses into or out of a terminal:
  `TerminalOutputFilter` drops escape sequences a hostile server could
  abuse before output reaches the emulator; `PastedText` cleans pastes and
  typed saved commands; `DictatedText` makes speech safe to type.
  `CommandSecrets` spots passwords and tokens in commands about to be
  saved.
- **Storage.** `Library`, the `@Observable` store the UI reads. JSON
  documents go to a `LibraryStorage`. Passwords and private keys go to a
  `SecretStore`: the Keychain on iOS, in memory in tests.

## PortlightSSH

- `SSHConnection.connect` runs TCP, then the SSH handshake with an async
  host-key validator. The handshake timer pauses while the user decides.
  Credentials are tried in order. A `jump` connection makes it run inside
  a direct-tcpip channel instead of a socket.
- `SSHShell` is a PTY session. Output arrives as an `AsyncStream`; input,
  resize and close are methods. `OutputFlow` stops reading from the
  channel when the consumer falls behind, so a fast server pauses instead
  of filling memory.
- `TerminalSession` is one tab. It resolves the jump chain from the
  library, prompts for host keys and passwords through observable prompt
  objects, starts the shell, buffers output until a view attaches, and
  reports how the session ended. `SessionManager` holds the tabs.
- `SecureEnclaveKeys` creates and uses Secure Enclave keys (Apple only).

## App

- `AppModel` owns the `Library`, `SessionManager` and `AppLock`, plus one
  long-lived `TerminalController` per open tab. Terminal screens therefore
  survive app locking and tab switches.
- `RootView` shows `LockScreenView` until unlocked and re-locks after a
  real trip to the background. `PrivacyShield` covers the whole app, sheets
  and terminal included, in its own window whenever it isn't active.
- `TerminalController` owns a `PortlightTerminalView` (SwiftTerm), its
  `KeyBarView`, and the delegate callbacks into the session.
- `TerminalScreen` lays out the tab bar (text size, rotation, options), the
  terminal and the voice strip (`VoiceInputView`, with `SpeechDictation`
  for on-device recognition). `KeyboardInset` makes room for the keyboard
  and `OrientationLock` turns the screen.

## Testing

`PortlightCore/Tests` has unit tests for every PortlightKit component. The
fixtures come from real `ssh-keygen` and `openssl` output, and bcrypt-pbkdf
values from pyca/bcrypt. Integration tests run `PortlightSSH` against a real
`sshd` started on 127.0.0.1 by `TestSSHServer`.
