import Foundation

/// Where passwords and private keys live. On iOS this is the Keychain
/// (`KeychainSecretStore`); tests use `InMemorySecretStore`.
public protocol SecretStore: Sendable {
    func data(for account: String) throws -> Data?
    func set(_ data: Data, for account: String) throws
    func delete(_ account: String) throws
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

    public var accounts: [String] { lock.withLock { Array(values.keys).sorted() } }
}

#if canImport(Security)
import Security

/// Keychain storage: generic passwords in Portlight's service, readable only
/// while the device is unlocked, never synced to iCloud or included in
/// backups (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
public struct KeychainSecretStore: SecretStore {
    public struct KeychainError: Error, CustomStringConvertible {
        public let status: OSStatus
        public var description: String { "Keychain error \(status)" }
    }

    public let service: String

    public init(service: String = "dev.portlight.secrets") {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func data(for account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return item as? Data
    }

    public func set(_ data: Data, for account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(account)
            add.merge(attributes) { $1 }
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
#endif
