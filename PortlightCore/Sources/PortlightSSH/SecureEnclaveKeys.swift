#if canImport(Darwin) && canImport(CryptoKit) && canImport(LocalAuthentication)
import CryptoKit
import Foundation
import LocalAuthentication
import NIOSSH
import PortlightKit
import Security

/// SSH keys created inside the Secure Enclave. The private key never leaves
/// the chip: Portlight keeps only an opaque, device-bound handle (in the
/// Keychain). Signing needs Face ID, Touch ID or the passcode; the context
/// the app unlocked with satisfies that, so signatures don't prompt again
/// until the app locks and the context is invalidated.
public enum SecureEnclaveKeys {
    public enum Failure: Error, LocalizedError {
        case unavailable
        case accessControl

        public var errorDescription: String? {
            switch self {
            case .unavailable: "This device has no Secure Enclave."
            case .accessControl: "Couldn't set up the key's protection."
            }
        }
    }

    public static var isAvailable: Bool { SecureEnclave.isAvailable }

    private static func accessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.privateKeyUsage, .userPresence], &error) else {
            throw Failure.accessControl
        }
        return access
    }

    /// Creates a key. Returns the handle to store and its public key.
    public static func create(context: LAContext?) throws -> (handle: Data, publicKey: SSHPublicKey) {
        guard isAvailable else { throw Failure.unavailable }
        let key = try SecureEnclave.P256.Signing.PrivateKey(
            compactRepresentable: false, accessControl: try accessControl(), authenticationContext: context)
        let publicKey = try SSHPublicKey.ecdsaP256(x963Representation: Array(key.publicKey.x963Representation))
        return (key.dataRepresentation, publicKey)
    }

    /// The credential for a stored handle.
    public static func credential(handle: Data, context: LAContext?) throws -> SSHCredential {
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: handle, authenticationContext: context)
        return .privateKey(NIOSSHPrivateKey(secureEnclaveP256Key: key))
    }
}
#endif
