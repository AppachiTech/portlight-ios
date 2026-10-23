// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Portlight",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PortlightKit", targets: ["PortlightKit"]),
        .library(name: "PortlightSSH", targets: ["PortlightSSH"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.15.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.86.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.12.0"..<"6.0.0"),
    ],
    targets: [
        .target(
            name: "PortlightKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .target(
            name: "PortlightSSH",
            dependencies: [
                "PortlightKit",
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            ]
        ),
        .testTarget(name: "PortlightKitTests", dependencies: ["PortlightKit"]),
        .testTarget(name: "PortlightSSHTests", dependencies: ["PortlightSSH"]),
    ]
)
