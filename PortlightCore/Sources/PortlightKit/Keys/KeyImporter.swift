import Crypto
import Foundation

/// Turns whatever a user pastes or picks from Files into a usable key, or a
/// clear reason why not.
public enum KeyImporter {
    public struct Imported: Sendable {
        public let key: SSHPrivateKey
        public let comment: String
    }

    /// What kind of key text this is, so the UI can ask for a passphrase
    /// before trying to import.
    public enum Inspection: Equatable, Sendable {
        case openSSH(encrypted: Bool)
        case pem
        case unsupported(SSHKeyError)
    }

    public static func inspect(_ text: String) -> Inspection {
        guard let label = PEM.firstLabel(in: text) else {
            if text.contains("PuTTY-User-Key-File") {
                return .unsupported(.unsupportedKeyType("PuTTY .ppk (convert it with puttygen to OpenSSH format)"))
            }
            if (try? SSHPublicKey(openSSH: text.trimmingCharacters(in: .whitespacesAndNewlines))) != nil {
                return .unsupported(.unsupportedKeyType("this is a public key; paste the private key instead"))
            }
            return .unsupported(.unrecognizedFormat)
        }
        switch label {
        case OpenSSHKeyFile.pemLabel:
            do {
                return .openSSH(encrypted: try OpenSSHKeyFile.isEncrypted(pem: text))
            } catch let error as SSHKeyError {
                return .unsupported(error)
            } catch {
                return .unsupported(.unrecognizedFormat)
            }
        case "EC PRIVATE KEY", "PRIVATE KEY":
            if text.contains("Proc-Type: 4,ENCRYPTED") {
                return .unsupported(.unsupportedCipher("legacy encrypted PEM (run ssh-keygen -p -f <file> to convert it to OpenSSH format)"))
            }
            return .pem
        case "RSA PRIVATE KEY":
            return .unsupported(.unsupportedKeyType("RSA"))
        case "DSA PRIVATE KEY":
            return .unsupported(.unsupportedKeyType("DSA"))
        case "ENCRYPTED PRIVATE KEY":
            return .unsupported(.unsupportedCipher("encrypted PKCS#8 (run ssh-keygen -p -f <file> to convert it to OpenSSH format)"))
        default:
            return .unsupported(.unrecognizedFormat)
        }
    }

    public static func importKey(_ text: String, passphrase: String? = nil) throws -> Imported {
        switch inspect(text) {
        case .unsupported(let error):
            throw error
        case .openSSH:
            let (key, comment) = try OpenSSHKeyFile.decode(pem: text, passphrase: passphrase)
            return Imported(key: key, comment: comment)
        case .pem:
            return Imported(key: try importPEM(text), comment: "")
        }
    }

    /// Ed25519 PKCS#8 is a fixed 48-byte DER structure ending in the seed.
    private static let ed25519PKCS8Prefix: [UInt8] = [
        0x30, 0x2E, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20,
    ]
    /// DER of the rsaEncryption OID, to recognise RSA inside PKCS#8.
    private static let rsaOID: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]

    static func importPEM(_ text: String) throws -> SSHPrivateKey {
        if let p256 = try? P256.Signing.PrivateKey(pemRepresentation: text) { return .ecdsaP256(p256) }
        if let p384 = try? P384.Signing.PrivateKey(pemRepresentation: text) { return .ecdsaP384(p384) }
        if let p521 = try? P521.Signing.PrivateKey(pemRepresentation: text) { return .ecdsaP521(p521) }
        if let der = PEM.body(of: text, label: "PRIVATE KEY") {
            if der.count == 48, Array(der.prefix(16)) == ed25519PKCS8Prefix {
                return try SSHPrivateKey(algorithm: .ed25519, rawScalar: Array(der.suffix(32)))
            }
            if der.windows(ofCount: rsaOID.count).contains(where: { Array($0) == rsaOID }) {
                throw SSHKeyError.unsupportedKeyType("RSA")
            }
        }
        throw SSHKeyError.unrecognizedFormat
    }
}

extension Array {
    /// Every contiguous slice of `count` elements (a small stand-in for
    /// swift-algorithms' `windows(ofCount:)`).
    func windows(ofCount count: Int) -> [ArraySlice<Element>] {
        guard count > 0, self.count >= count else { return [] }
        return (0...(self.count - count)).map { self[$0..<$0 + count] }
    }
}

extension SSHKeyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPublicKey: "That isn't a valid SSH public key."
        case .unrecognizedFormat: "That doesn't look like an SSH private key Portlight can read."
        case .passphraseRequired: "This key is protected by a passphrase."
        case .wrongPassphrase: "That passphrase doesn't unlock this key."
        case .unsupportedKeyType(let type) where type == "RSA":
            "RSA keys aren't supported yet. Generate an Ed25519 key in Portlight and add its public key to the server, or create an ED25519 key pair in your cloud console."
        case .unsupportedKeyType(let type): "Unsupported key: \(type)."
        case .unsupportedCipher(let name): "This key is encrypted in a way Portlight can't read: \(name)."
        case .unsupportedKDF(let name): "Unsupported key derivation: \(name)."
        case .corrupt(let detail): "The key file is damaged (\(detail))."
        }
    }
}
