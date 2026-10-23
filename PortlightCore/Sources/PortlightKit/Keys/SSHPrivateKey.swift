import Crypto
import Foundation

/// A user private key Portlight can authenticate with.
public enum SSHPrivateKey: Sendable {
    case ed25519(Curve25519.Signing.PrivateKey)
    case ecdsaP256(P256.Signing.PrivateKey)
    case ecdsaP384(P384.Signing.PrivateKey)
    case ecdsaP521(P521.Signing.PrivateKey)

    /// A fresh random key.
    public static func generate(_ algorithm: KeyAlgorithm) -> SSHPrivateKey {
        switch algorithm {
        case .ed25519: .ed25519(.init())
        case .ecdsaP256: .ecdsaP256(.init())
        case .ecdsaP384: .ecdsaP384(.init())
        case .ecdsaP521: .ecdsaP521(.init())
        }
    }

    public var algorithm: KeyAlgorithm {
        switch self {
        case .ed25519: .ed25519
        case .ecdsaP256: .ecdsaP256
        case .ecdsaP384: .ecdsaP384
        case .ecdsaP521: .ecdsaP521
        }
    }

    /// The private scalar (Ed25519: the 32-byte seed).
    public var rawScalar: [UInt8] {
        switch self {
        case .ed25519(let key): Array(key.rawRepresentation)
        case .ecdsaP256(let key): Array(key.rawRepresentation)
        case .ecdsaP384(let key): Array(key.rawRepresentation)
        case .ecdsaP521(let key): Array(key.rawRepresentation)
        }
    }

    /// Rebuilds a key from its algorithm and private scalar.
    public init(algorithm: KeyAlgorithm, rawScalar: [UInt8]) throws {
        let scalar = rawScalar.leftPadded(to: algorithm.scalarLength)
        switch algorithm {
        case .ed25519: self = .ed25519(try .init(rawRepresentation: scalar))
        case .ecdsaP256: self = .ecdsaP256(try .init(rawRepresentation: scalar))
        case .ecdsaP384: self = .ecdsaP384(try .init(rawRepresentation: scalar))
        case .ecdsaP521: self = .ecdsaP521(try .init(rawRepresentation: scalar))
        }
    }

    /// Ed25519: the 32-byte public key. ECDSA: the uncompressed point Q.
    var publicPoint: [UInt8] {
        switch self {
        case .ed25519(let key): Array(key.publicKey.rawRepresentation)
        case .ecdsaP256(let key): Array(key.publicKey.x963Representation)
        case .ecdsaP384(let key): Array(key.publicKey.x963Representation)
        case .ecdsaP521(let key): Array(key.publicKey.x963Representation)
        }
    }

    public var publicKey: SSHPublicKey {
        SSHPublicKey(algorithm: algorithm, point: publicPoint)
    }

    /// Signs `data` and returns the raw signature (for tests and self-checks;
    /// SSH authentication signing happens inside SwiftNIO SSH).
    func sign(_ data: [UInt8]) throws -> [UInt8] {
        switch self {
        case .ed25519(let key): Array(try key.signature(for: data))
        case .ecdsaP256(let key): Array(try key.signature(for: data).rawRepresentation)
        case .ecdsaP384(let key): Array(try key.signature(for: data).rawRepresentation)
        case .ecdsaP521(let key): Array(try key.signature(for: data).rawRepresentation)
        }
    }
}

/// A public key in SSH form, for user keys and server host keys alike.
public struct SSHPublicKey: Hashable, Sendable {
    public let algorithmName: String
    /// The full SSH wire blob: what `authorized_keys` base64-encodes and what
    /// fingerprints are computed over.
    public let blob: [UInt8]

    init(algorithm: KeyAlgorithm, point: [UInt8]) {
        var writer = SSHWriter()
        writer.writeString(algorithm.sshName)
        if let curve = algorithm.curveName { writer.writeString(curve) }
        writer.writeString(point)
        self.algorithmName = algorithm.sshName
        self.blob = writer.bytes
    }

    /// The public half of a P-256 key held elsewhere (the Secure Enclave),
    /// from its uncompressed X9.63 point.
    public static func ecdsaP256(x963Representation point: [UInt8]) throws -> SSHPublicKey {
        guard point.count == 65, point.first == 0x04 else { throw SSHKeyError.invalidPublicKey }
        return SSHPublicKey(algorithm: .ecdsaP256, point: point)
    }

    /// Wraps a wire blob from a server or a file. Any algorithm is accepted
    /// here (host keys may be RSA); only the name is checked against the blob.
    public init(blob: [UInt8]) throws {
        var reader = SSHReader(blob)
        self.algorithmName = try reader.readUTF8String()
        self.blob = blob
    }

    /// Parses one `authorized_keys`-style line: `type base64 [comment]`.
    public init(openSSH line: String) throws {
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2, let blob = Base64.decode(fields[1]) else {
            throw SSHKeyError.invalidPublicKey
        }
        try self.init(blob: blob)
        guard algorithmName == String(fields[0]) else { throw SSHKeyError.invalidPublicKey }
    }

    /// `type base64 comment`, ready for `~/.ssh/authorized_keys`.
    public func openSSHString(comment: String? = nil) -> String {
        var line = "\(algorithmName) \(Base64.encode(blob))"
        if let comment, !comment.isEmpty { line += " \(comment)" }
        return line
    }

    /// The OpenSSH fingerprint, e.g. `SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s`.
    public var sha256Fingerprint: String {
        let digest = SHA256.hash(data: blob)
        let encoded = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:\(encoded)"
    }

    public var keyAlgorithm: KeyAlgorithm? { KeyAlgorithm(sshName: algorithmName) }
}

public enum SSHKeyError: Error, Equatable, Sendable {
    case invalidPublicKey
    case unrecognizedFormat
    /// The file is encrypted and no passphrase was given.
    case passphraseRequired
    /// The passphrase did not decrypt the key.
    case wrongPassphrase
    /// RSA and DSA keys cannot be used with SwiftNIO SSH.
    case unsupportedKeyType(String)
    case unsupportedCipher(String)
    case unsupportedKDF(String)
    case corrupt(String)
}
