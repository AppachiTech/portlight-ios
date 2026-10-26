import Foundation

/// Where passwords and private keys live. On iOS this is the Keychain
/// (`KeychainSecretStore`); tests use `InMemorySecretStore`.
public protocol SecretStore: Sendable {
    func data(for account: String) throws -> Data?
    func set(_ data: Data, for account: String) throws
    func delete(_ account: String) throws
    /// Removes every secret this store holds.
    func deleteAll() throws
}

public enum SecretAccount {
    public static func privateKey(_ id: UUID) -> String { "key.\(id.uuidString)" }
    public static func password(_ hostID: UUID) -> String { "password.\(hostID.uuidString)" }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func data(for account: String) throws -> Data? {
        lock.withLock { values[account] }
    }

    public func set(_ data: Data, for account: String) throws {
        lock.withLock { values[account] = data }
    }

    public func delete(_ account: String) throws {
        _ = lock.withLock { values.removeValue(forKey: account) }
    }

    public func deleteAll() throws {
        lock.withLock { values.removeAll() }
    }

    public var accounts: [String] { lock.withLock { Array(values.keys).sorted() } }
}

#if canImport(Security)
import Security
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Keychain storage, hardened:
///
/// - `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`: readable only while
///   the device is unlocked, never synced to iCloud or restored to another
///   device, and destroyed if the passcode is removed.
/// - Access control `.userPresence`: iOS itself refuses to release the item
///   without Face ID, Touch ID or the passcode, so the protection doesn't
///   depend on the app's lock screen alone. The app passes the
///   `LAContext` it unlocked with, so the user isn't asked twice.
public struct KeychainSecretStore: SecretStore {
    public struct KeychainError: Error, CustomStringConvertible {
        public let status: OSStatus
        public var description: String {
            switch status {
            case errSecUserCanceled: "Authentication was cancelled."
            case errSecAuthFailed: "Authentication failed."
            case errSecInteractionNotAllowed: "The device is locked."
            default: "Keychain error \(status)"
            }
        }
    }

    public let service: String
    /// Whether items require user presence. Off only for unit tests on a
    /// Mac without the data-protection keychain entitlement.
    public let requireUserPresence: Bool
    #if canImport(LocalAuthentication)
    /// The authenticated context to read with; nil lets iOS prompt itself.
    public let authenticationContext: @Sendable () -> LAContext?
    #endif

    #if canImport(LocalAuthentication)
    public init(service: String = "dev.portlight.secrets", requireUserPresence: Bool = true,
                authenticationContext: @escaping @Sendable () -> LAContext? = { nil }) {
        self.service = service
        self.requireUserPresence = requireUserPresence
        self.authenticationContext = authenticationContext
    }
    #else
    public init(service: String = "dev.portlight.secrets", requireUserPresence: Bool = true) {
        self.service = service
        self.requireUserPresence = requireUserPresence
    }
    #endif

    private func baseQuery(_ account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        #if canImport(LocalAuthentication)
        if let context = authenticationContext() {
            query[kSecUseAuthenticationContext as String] = context
        }
        #endif
        return query
    }

    public func data(for account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return item as? Data
    }

    public func set(_ data: Data, for account: String) throws {
        // Delete then add, so the access control is always the current one.
        try delete(account)
        var add = baseQuery(account)
        add[kSecValueData as String] = data
        if requireUserPresence {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error) else {
                throw KeychainError(status: errSecParam)
            }
            add[kSecAttrAccessControl as String] = access
        } else {
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete(_ account: String) throws {
        var query = baseQuery(account)
        query.removeValue(forKey: kSecUseAuthenticationContext as String)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    public func deleteAll() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
#endif
