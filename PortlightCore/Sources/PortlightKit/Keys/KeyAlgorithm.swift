import Foundation

/// The SSH user-key algorithms Portlight can generate, import and use.
///
/// RSA is deliberately absent: SwiftNIO SSH, the SSH implementation
/// Portlight builds on, does not support RSA keys. See docs/SECURITY.md.
public enum KeyAlgorithm: String, Codable, CaseIterable, Sendable {
    case ed25519
    case ecdsaP256
    case ecdsaP384
    case ecdsaP521

    /// The algorithm name used in public keys and key files.
    public var sshName: String {
        switch self {
        case .ed25519: "ssh-ed25519"
        case .ecdsaP256: "ecdsa-sha2-nistp256"
        case .ecdsaP384: "ecdsa-sha2-nistp384"
        case .ecdsaP521: "ecdsa-sha2-nistp521"
        }
    }

    /// The curve identifier inside ECDSA key blobs.
    var curveName: String? {
        switch self {
        case .ed25519: nil
        case .ecdsaP256: "nistp256"
        case .ecdsaP384: "nistp384"
        case .ecdsaP521: "nistp521"
        }
    }

    /// Byte length of the private scalar.
    var scalarLength: Int {
        switch self {
        case .ed25519: 32
        case .ecdsaP256: 32
        case .ecdsaP384: 48
        case .ecdsaP521: 66
        }
    }

    public var displayName: String {
        switch self {
        case .ed25519: "Ed25519"
        case .ecdsaP256: "ECDSA P-256"
        case .ecdsaP384: "ECDSA P-384"
        case .ecdsaP521: "ECDSA P-521"
        }
    }

    public init?(sshName: String) {
        guard let match = Self.allCases.first(where: { $0.sshName == sshName }) else { return nil }
        self = match
    }
}
