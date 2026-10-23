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
  export, hashed names) and `AppLockPolicy`.
- **Terminal.** `KeyEncoder` (xterm sequences for the key bar),
  `StickyModifiers`, `TerminalTheme`, `AppSettings`, `Snippet`.
- **Storage.** `Library`, the `@Observable` store the UI reads. JSON
  documents go to a `LibraryStorage`. Passwords and private keys go to a
  `SecretStore`: the Keychain on iOS, in memory in tests.

## PortlightSSH

- `SSHConnection.connect` runs TCP, then the SSH handshake with an async
  host-key validator. The handshake timer pauses while the user decides.
  Credentials are tried in order. A `jump` connection makes it run inside
  a direct-tcpip channel instead of a socket.
- `SSHShell` is a PTY session. Output arrives as an `AsyncStream`; input,
  resize and close are methods.
- `TerminalSession` is one tab. It resolves the jump chain from the
  library, prompts for host keys and passwords through observable prompt
  objects, starts the shell, buffers output until a view attaches, and
  reports how the session ended. `SessionManager` holds the tabs.
- `SecureEnclaveKeys` creates and uses Secure Enclave keys (Apple only).

## App

- `AppModel` owns the `Library`, `SessionManager` and `AppLock`, plus one
  long-lived `TerminalController` per open tab. Terminal screens therefore
  survive app locking and tab switches.
- `RootView` shows `LockScreenView` until unlocked, overlays a privacy
  cover when not active, and re-locks after a real trip to the background.
- `TerminalController` owns a `PortlightTerminalView` (SwiftTerm), its
  `KeyBarView`, and the delegate callbacks into the session.

## Testing

`PortlightCore/Tests` has unit tests for every PortlightKit component. The
fixtures come from real `ssh-keygen` and `openssl` output, and bcrypt-pbkdf
values from pyca/bcrypt. Integration tests run `PortlightSSH` against a real
`sshd` started on 127.0.0.1 by `TestSSHServer`.
