import Foundation
import NIOCore
import NIOSSH
import PortlightKit

/// The terminal's size in character cells (and optionally pixels).
public struct TerminalSize: Hashable, Sendable {
    public var columns: Int
    public var rows: Int
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(columns: Int, rows: Int, pixelWidth: Int = 0, pixelHeight: Int = 0) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.pixelWidth = max(0, pixelWidth)
        self.pixelHeight = max(0, pixelHeight)
    }

    public static let standard = TerminalSize(columns: 80, rows: 24)
}

/// A way to log in, tried in the order given.
public enum SSHCredential: Sendable {
    case password(String)
    case privateKey(NIOSSHPrivateKey)

    public static func key(_ key: SSHPrivateKey) -> SSHCredential {
        .privateKey(key.nioKey)
    }
}

extension SSHPrivateKey {
    /// The same key as SwiftNIO SSH's type.
    public var nioKey: NIOSSHPrivateKey {
        switch self {
        case .ed25519(let key): NIOSSHPrivateKey(ed25519Key: key)
        case .ecdsaP256(let key): NIOSSHPrivateKey(p256Key: key)
        case .ecdsaP384(let key): NIOSSHPrivateKey(p384Key: key)
        case .ecdsaP521(let key): NIOSSHPrivateKey(p521Key: key)
        }
    }
}

/// Where to connect and as whom.
public struct SSHEndpoint: Sendable {
    public var host: String
    public var port: Int
    public var username: String
    public var credentials: [SSHCredential]

    public init(host: String, port: Int = 22, username: String, credentials: [SSHCredential]) {
        self.host = host
        self.port = port
        self.username = username
        self.credentials = credentials
    }
}

/// The key a server presented, for the app to check against known hosts
/// (and ask the user about when it's new or changed).
public struct HostKeyChallenge: Sendable {
    public let host: String
    public let port: Int
    public let key: SSHPublicKey
}

/// Decides whether to trust a host key. May take as long as it likes (for
/// example, while the user compares a fingerprint): connection timeouts are
/// paused until it returns.
public typealias HostKeyValidator = @Sendable (HostKeyChallenge) async -> Bool

/// Connection tuning.
public struct SSHConnectionOptions: Sendable {
    /// TCP connect timeout.
    public var connectTimeout: TimeAmount = .seconds(15)
    /// Time allowed for each stage of the handshake (key exchange, then
    /// authentication), not counting time spent in the host key validator.
    public var handshakeTimeout: TimeAmount = .seconds(30)
    /// Seconds of idleness before TCP keepalive probes start; 0 disables.
    public var keepAliveInterval: Int = 30

    public init() {}
}

/// Why a connection failed, in terms the app can show.
public enum SSHConnectionError: Error, Equatable, Sendable, LocalizedError {
    case hostKeyRejected(SSHPublicKey)
    case authenticationFailed(username: String)
    case connectionFailed(String)
    case timedOut
    case disconnected
    case channelRejected(String)
    case unsupportedHostKey(String)

    public var errorDescription: String? {
        switch self {
        case .hostKeyRejected:
            "The server's host key wasn't trusted, so Portlight disconnected."
        case .authenticationFailed(let username):
            "The server didn't accept the credentials for \(username)."
        case .connectionFailed(let reason):
            "Couldn't connect: \(reason)"
        case .timedOut:
            "The server stopped responding."
        case .disconnected:
            "The connection closed."
        case .channelRejected(let what):
            "The server refused to \(what)."
        case .unsupportedHostKey(let type):
            "The server's host key type (\(type)) isn't supported."
        }
    }
}

/// What an interactive shell reports.
public enum ShellEvent: Sendable, Equatable {
    /// Bytes for the terminal (stdout and stderr interleaved, as a TTY does).
    case output([UInt8])
    /// The remote shell ended. Either value may be missing.
    case exited(status: Int?, signal: String?)
}
