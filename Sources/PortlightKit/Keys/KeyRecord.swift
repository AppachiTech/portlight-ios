import Foundation

/// Where a key's private half lives.
public enum KeyStorage: String, Codable, Sendable {
    /// An OpenSSH key file in the Keychain. Can be exported.
    case keychain
    /// A P-256 key created inside the Secure Enclave. It never leaves the
    /// chip and can't be exported or backed up; the Keychain holds only an
    /// opaque handle to it.
    case secureEnclave
}

/// A saved key as listed in the app. The private half is in the
/// `SecretStore` under `SecretAccount.privateKey(id)`.
public struct KeyRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var algorithm: KeyAlgorithm
    public var publicKeyBlob: Data
    public var storage: KeyStorage
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, publicKey: SSHPublicKey, storage: KeyStorage, createdAt: Date = Date()) throws {
        guard let algorithm = publicKey.keyAlgorithm else { throw SSHKeyError.unsupportedKeyType(publicKey.algorithmName) }
        self.id = id
        self.name = name
        self.algorithm = algorithm
        self.publicKeyBlob = Data(publicKey.blob)
        self.storage = storage
        self.createdAt = createdAt
    }

    public var publicKey: SSHPublicKey {
        // Validated in init; a record decoded from disk with a bad blob would
        // be caught by `Library.load`.
        (try? SSHPublicKey(blob: Array(publicKeyBlob))) ?? SSHPublicKey(algorithm: algorithm, point: [])
    }

    public var fingerprint: String { publicKey.sha256Fingerprint }
}
