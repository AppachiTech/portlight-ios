# Third-party licenses

Portlight is MIT licensed (see [LICENSE](LICENSE)). The app is built on the
open-source packages below. Versions are the ones pinned in
[`PortlightCore/Package.resolved`](PortlightCore/Package.resolved); each
package's full license text is in its repository.

## Linked into the app

| Package | Version | License | Copyright |
| --- | --- | --- | --- |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | 1.20.0 | MIT | Miguel de Icaza |
| [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) | 0.15.0 | Apache 2.0 | Apple Inc. and the SwiftNIO project authors |
| [SwiftNIO](https://github.com/apple/swift-nio) | 2.104.0 | Apache 2.0 | Apple Inc. and the SwiftNIO project authors |
| [Swift Crypto](https://github.com/apple/swift-crypto) | 4.5.2 | Apache 2.0 | Apple Inc. and the SwiftCrypto project authors |
| [Swift ASN.1](https://github.com/apple/swift-asn1) | 1.7.3 | Apache 2.0 | Apple Inc. and the SwiftASN1 project authors |
| [Swift Atomics](https://github.com/apple/swift-atomics) | 1.3.1 | Apache 2.0 with Runtime Library Exception | Apple Inc. and the Swift project authors |
| [Swift Collections](https://github.com/apple/swift-collections) | 1.7.4 | Apache 2.0 with Runtime Library Exception | Apple Inc. and the Swift project authors |
| [Swift System](https://github.com/apple/swift-system) | 1.8.1 | Apache 2.0 with Runtime Library Exception | Apple Inc. and the Swift project authors |

SwiftNIO, Swift Crypto and Swift ASN.1 include `NOTICE.txt` files; their
notices apply to binaries built from this repository. On Apple platforms
Swift Crypto uses CryptoKit, so its bundled BoringSSL is not part of the
iOS app.

## Used only to build

| Package | License | Used for |
| --- | --- | --- |
| [Swift Argument Parser](https://github.com/apple/swift-argument-parser) | Apache 2.0 with Runtime Library Exception | A SwiftTerm command-line target; not linked into the app |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | MIT | Generating the Xcode project |
