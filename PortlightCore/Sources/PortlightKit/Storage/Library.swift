import Foundation
import Observation

/// Everything the user has saved: hosts, keys, trusted host keys, snippets
/// and settings. JSON documents go to `LibraryStorage`; passwords and private
/// keys go to the `SecretStore` and never touch those files.
@Observable
@MainActor
public final class Library {
    public private(set) var hosts: [SSHHost] = []
    public private(set) var keys: [KeyRecord] = []
    public private(set) var knownHosts = KnownHosts()
    public private(set) var snippets: [Snippet] = []
    public var settings = AppSettings() {
        didSet { if settings != oldValue { persist(settings, Files.settings) } }
    }
    /// The last storage failure, for the UI to surface.
    public private(set) var lastError: String?

    @ObservationIgnored let storage: LibraryStorage
    @ObservationIgnored public let secrets: SecretStore

    enum Files {
        static let hosts = "hosts.json"
        static let keys = "keys.json"
        static let knownHosts = "known_hosts.json"
        static let snippets = "snippets.json"
        static let settings = "settings.json"
    }

    public init(storage: LibraryStorage, secrets: SecretStore) {
        self.storage = storage
        self.secrets = secrets
        hosts = load([SSHHost].self, Files.hosts) ?? []
        keys = (load([KeyRecord].self, Files.keys) ?? []).filter { $0.publicKey.keyAlgorithm != nil }
        knownHosts = load(KnownHosts.self, Files.knownHosts) ?? KnownHosts()
        snippets = load([Snippet].self, Files.snippets) ?? Snippet.starters
        settings = load(AppSettings.self, Files.settings) ?? AppSettings()
    }

    // MARK: Hosts

    /// Adds the host, or replaces the saved one with the same id.
    public func save(_ host: SSHHost) throws {
        let problems = host.validate()
        if let first = problems.first { throw first }
        if let jump = host.jumpHostID {
            var draft = hosts.filter { $0.id != host.id }
            draft.append(host)
            guard (try? jumpChain(for: host.id, in: draft)) != nil, jump != host.id else {
                throw LibraryError.jumpLoop
            }
        }
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        persist(hosts, Files.hosts)
    }

    public func delete(_ host: SSHHost) {
        hosts.removeAll { $0.id == host.id }
        for index in hosts.indices where hosts[index].jumpHostID == host.id {
            hosts[index].jumpHostID = nil
        }
        try? secrets.delete(SecretAccount.password(host.id))
        persist(hosts, Files.hosts)
    }

    public func duplicate(_ host: SSHHost) throws -> SSHHost {
        var copy = host
        copy.id = UUID()
        copy.label = host.displayName + " copy"
        copy.createdAt = Date()
        copy.lastConnectedAt = nil
        try save(copy)
        return copy
    }

    public func host(_ id: UUID?) -> SSHHost? {
        guard let id else { return nil }
        return hosts.first { $0.id == id }
    }

    public func markConnected(_ hostID: UUID, at date: Date = Date()) {
        guard let index = hosts.firstIndex(where: { $0.id == hostID }) else { return }
        hosts[index].lastConnectedAt = date
        persist(hosts, Files.hosts)
    }

    /// The hops to reach a host, outermost first, ending with the host.
    public func jumpChain(for hostID: UUID) throws -> [SSHHost] {
        try jumpChain(for: hostID, in: hosts)
    }

    func jumpChain(for hostID: UUID, in list: [SSHHost]) throws -> [SSHHost] {
        var chain: [SSHHost] = []
        var seen: Set<UUID> = []
        var current: UUID? = hostID
        while let id = current {
            guard seen.insert(id).inserted else { throw LibraryError.jumpLoop }
            guard let host = list.first(where: { $0.id == id }) else { throw LibraryError.missingJumpHost }
            chain.insert(host, at: 0)
            current = host.jumpHostID
        }
        guard chain.count <= 4 else { throw LibraryError.jumpChainTooLong }
        return chain
    }

    public struct Section: Identifiable, Equatable {
        public var title: String
        public var hosts: [SSHHost]
        public var id: String { title }
    }

    /// The host list as shown: recent hosts first (when not searching), then
    /// one section per group, sorted by name.
    public func sections(matching query: String = "") -> [Section] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = hosts.filter { host in
            needle.isEmpty || [host.displayName, host.hostname, host.username, host.group ?? "", host.provider.displayName]
                .contains { $0.lowercased().contains(needle) }
        }
        var result: [Section] = []
        if needle.isEmpty {
            let recent = matching.filter { $0.lastConnectedAt != nil }
                .sorted { $0.lastConnectedAt! > $1.lastConnectedAt! }
                .prefix(3)
            if !recent.isEmpty, matching.count > 4 { result.append(Section(title: "Recent", hosts: Array(recent))) }
        }
        let grouped = Dictionary(grouping: matching) { host -> String in
            let group = host.group?.trimmingCharacters(in: .whitespaces) ?? ""
            return group.isEmpty ? "Hosts" : group
        }
        let order = grouped.keys.sorted { a, b in
            if a == "Hosts" { return true }
            if b == "Hosts" { return false }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        for title in order {
            let sorted = grouped[title]!.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            result.append(Section(title: title, hosts: sorted))
        }
        return result
    }

    public var groups: [String] {
        Array(Set(hosts.compactMap { $0.group?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
    }

    // MARK: Passwords

    public func password(for hostID: UUID) -> String? {
        guard let data = try? secrets.data(for: SecretAccount.password(hostID)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setPassword(_ password: String?, for hostID: UUID) throws {
        if let password, !password.isEmpty {
            try secrets.set(Data(password.utf8), for: SecretAccount.password(hostID))
        } else {
            try secrets.delete(SecretAccount.password(hostID))
        }
    }

    // MARK: Keys

    public func key(_ id: UUID?) -> KeyRecord? {
        guard let id else { return nil }
        return keys.first { $0.id == id }
    }

    @discardableResult
    public func generateKey(named name: String, algorithm: KeyAlgorithm = .ed25519) throws -> KeyRecord {
        let key = SSHPrivateKey.generate(algorithm)
        return try store(key, name: name)
    }

    @discardableResult
    public func importKey(_ text: String, passphrase: String? = nil, name: String? = nil) throws -> KeyRecord {
        let imported = try KeyImporter.importKey(text, passphrase: passphrase)
        if let existing = keys.first(where: { $0.publicKeyBlob == Data(imported.key.publicKey.blob) }) {
            throw LibraryError.duplicateKey(existing.name)
        }
        let fallback = imported.comment.isEmpty ? "Imported \(imported.key.algorithm.displayName) key" : imported.comment
        let chosen = name?.trimmingCharacters(in: .whitespaces)
        return try store(imported.key, name: (chosen?.isEmpty ?? true) ? fallback : chosen!)
    }

    private func store(_ key: SSHPrivateKey, name: String) throws -> KeyRecord {
        let record = try KeyRecord(name: name, publicKey: key.publicKey, storage: .keychain)
        // Stored unencrypted inside the Keychain item, which is itself
        // encrypted by the device and readable only while unlocked.
        let pem = try OpenSSHKeyFile.encode(key, comment: name, passphrase: nil)
        try secrets.set(Data(pem.utf8), for: SecretAccount.privateKey(record.id))
        keys.append(record)
        persist(keys, Files.keys)
        return record
    }

    /// Registers a key whose private half the caller already stored (the
    /// Secure Enclave path on iOS).
    public func addExternalKey(_ record: KeyRecord) {
        keys.append(record)
        persist(keys, Files.keys)
    }

    /// The private key for a Keychain-stored record.
    public func privateKey(for record: KeyRecord) throws -> SSHPrivateKey {
        guard record.storage == .keychain else { throw LibraryError.keyNotExportable }
        guard let data = try secrets.data(for: SecretAccount.privateKey(record.id)),
              let pem = String(data: data, encoding: .utf8) else { throw LibraryError.missingSecret }
        return try OpenSSHKeyFile.decode(pem: pem, passphrase: nil).key
    }

    /// Shortest passphrase accepted for exporting a private key.
    public nonisolated static let minimumExportPassphraseLength = 8

    /// The OpenSSH private key file, always encrypted (aes256-ctr, bcrypt):
    /// an exported key leaves the Keychain's protection, so it must carry its own.
    public func exportPrivateKey(_ record: KeyRecord, passphrase: String) throws -> String {
        guard record.storage == .keychain else { throw LibraryError.keyNotExportable }
        guard passphrase.count >= Self.minimumExportPassphraseLength else { throw LibraryError.weakExportPassphrase }
        return try OpenSSHKeyFile.encode(try privateKey(for: record), comment: record.name, passphrase: passphrase)
    }

    public func hostsUsing(_ record: KeyRecord) -> [SSHHost] {
        hosts.filter { $0.auth.keyID == record.id }
    }

    /// Deletes the key; hosts that used it fall back to password login.
    public func delete(_ record: KeyRecord) {
        keys.removeAll { $0.id == record.id }
        try? secrets.delete(SecretAccount.privateKey(record.id))
        var touched = false
        for index in hosts.indices where hosts[index].auth.keyID == record.id {
            hosts[index].auth = .password
            touched = true
        }
        persist(keys, Files.keys)
        if touched { persist(hosts, Files.hosts) }
    }

    public func rename(_ record: KeyRecord, to name: String) {
        guard let index = keys.firstIndex(where: { $0.id == record.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        keys[index].name = trimmed
        persist(keys, Files.keys)
    }

    // MARK: Known hosts

    public func hostKeyVerdict(host: String, port: Int, key: SSHPublicKey) -> HostKeyVerdict {
        knownHosts.verdict(host: host, port: port, key: key)
    }

    public func trustHostKey(host: String, port: Int, key: SSHPublicKey) {
        knownHosts.trust(host: host, port: port, key: key)
        persist(knownHosts, Files.knownHosts)
    }

    public func forgetHostKeys(host: String, port: Int) {
        knownHosts.forget(host: host, port: port)
        persist(knownHosts, Files.knownHosts)
    }

    public func removeKnownHost(_ entry: KnownHosts.Entry) {
        knownHosts.remove(entry)
        persist(knownHosts, Files.knownHosts)
    }

    @discardableResult
    public func importKnownHosts(_ text: String) -> Int {
        let added = knownHosts.importOpenSSH(text)
        if added > 0 { persist(knownHosts, Files.knownHosts) }
        return added
    }

    // MARK: SSH config

    /// Imports hosts from `~/.ssh/config` text. Returns what was added and
    /// anything that was skipped.
    public func importSSHConfig(_ text: String) -> (added: [SSHHost], warnings: [String]) {
        let parsed = SSHConfigParser.parse(text)
        let created = SSHConfigParser.makeHosts(from: parsed.entries, existing: hosts)
        var added: [SSHHost] = []
        var warnings = parsed.warnings
        for host in created {
            if let problem = host.validate().first {
                warnings.append("\(host.displayName): \(problem.localizedDescription)")
                continue
            }
            hosts.append(host)
            added.append(host)
        }
        if !added.isEmpty { persist(hosts, Files.hosts) }
        return (added, warnings)
    }

    // MARK: Snippets

    public func save(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.append(snippet)
        }
        persist(snippets, Files.snippets)
    }

    public func delete(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        persist(snippets, Files.snippets)
    }

    public func moveSnippets(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { snippets[$0] }
        var remaining = snippets.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let before = source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: min(destination - before, remaining.count))
        snippets = remaining
        persist(snippets, Files.snippets)
    }

    // MARK: Persistence

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        do {
            guard let data = try storage.read(name) else { return nil }
            return try Self.decoder.decode(type, from: data)
        } catch {
            lastError = "Couldn't read \(name): \(error.localizedDescription)"
            return nil
        }
    }

    private func persist<T: Encodable>(_ value: T, _ name: String) {
        do {
            try storage.write(try Self.encoder.encode(value), name: name)
        } catch {
            lastError = "Couldn't save \(name): \(error.localizedDescription)"
        }
    }
}

public enum LibraryError: Error, Equatable, LocalizedError {
    case jumpLoop
    case missingJumpHost
    case jumpChainTooLong
    case duplicateKey(String)
    case keyNotExportable
    case missingSecret
    case weakExportPassphrase

    public var errorDescription: String? {
        switch self {
        case .jumpLoop: "Those jump hosts lead back to each other."
        case .missingJumpHost: "The jump host no longer exists."
        case .jumpChainTooLong: "Portlight supports up to three jump hosts in a row."
        case .duplicateKey(let name): "That key is already saved as \"\(name)\"."
        case .keyNotExportable: "This key lives in the Secure Enclave and can't be exported."
        case .missingSecret: "The private key is missing from the Keychain."
        case .weakExportPassphrase: "Use a passphrase of at least \(Library.minimumExportPassphraseLength) characters to export a key."
        }
    }
}
