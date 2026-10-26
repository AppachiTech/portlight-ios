# Contributing to Portlight

Thanks for helping. Portlight holds the keys to people's servers, so changes
are judged on safety first and convenience second. Small, focused pull
requests with tests are the easiest to review and merge.

## Security problems

Please don't open a public issue for a vulnerability. Report it privately
with GitHub's **Security → Report a vulnerability** on this repository. See
[docs/SECURITY.md](docs/SECURITY.md) for what Portlight protects against and
its known limits.

## Getting set up

- The core package (`PortlightCore/`) builds and tests on macOS and Linux:

  ```sh
  make test
  ```

  The SSH integration tests start a throwaway `sshd` on 127.0.0.1 and need
  OpenSSH's `sshd` and `ssh-keygen`. Set `PORTLIGHT_SKIP_SSHD=1` to skip
  them.
- The app needs a Mac with Xcode and XcodeGen. [docs/BUILDING.md](docs/BUILDING.md)
  covers the first build, signing and common problems.

## Where changes go

- Protocol, crypto, parsing and anything else that can be tested without a
  phone belongs in `PortlightCore`, with tests. The app layer (`App/Portlight`)
  should stay thin.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the pieces fit.

## Pull requests

- **Tests.** Add or update tests for behaviour changes. For a bug fix,
  write a test that fails without the fix. `make test` must pass.
- **The app builds.** If you touch `App/`, build it for a device or
  simulator. CI builds it unsigned on every pull request.
- **Style.** Match the code around you: naming, comment density, and doc
  comments that say *why*. Keep diffs focused; unrelated reformatting makes
  review harder.
- **Security-sensitive areas** (host key checks, the Keychain, the app
  lock, key files, paste handling, terminal output filtering) get extra
  scrutiny. Say in the pull request what could go wrong and how the change
  guards against it.
- **Docs.** Update `docs/` and the README when behaviour users see changes.
  If a protection in docs/SECURITY.md changes, update it there too.
- **Commits.** Write messages that explain why, not just what. One logical
  change per commit is ideal.
- **Dependencies.** New packages need a good reason. Pin them in
  `Package.resolved`, and add them to [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

## Ideas that fit, and ones that don't

Welcome: terminal and SSH correctness, accessibility, iPad and keyboard
support, better error messages, and anything that makes connecting to cloud
servers safer or simpler.

Out of scope: accounts, sync services, analytics, ads, or anything that
sends data anywhere other than the servers the user connects to.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE). Everyone taking part is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
