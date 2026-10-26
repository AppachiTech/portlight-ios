import Crypto
import Foundation

/// What to do with the key a server presented.
public enum HostKeyVerdict: Equatable, Sendable {
    /// Seen and trusted before.
    case trusted
    /// No key on file for this host: ask the user to compare the fingerprint.
    case unknown
    /// A different key is on file, of the same type or another: possibly an
    /// attack, or the server was rebuilt. Refuse unless the user
    /// deliberately replaces it. A different type counts too, or an
    /// attacker could offer only a type you haven't trusted.
    case changed(previous: SSHPublicKey)
    /// The key is marked revoked.
    case revoked
}

/// Trust-on-first-use host key records, compatible with OpenSSH
/// `known_hosts` for import and export (including hashed hostnames).
public struct KnownHosts: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Hashable, Sendable {
        /// `hostname` for port 22, `[hostname]:port` otherwise, an OpenSSH
        /// `|1|salt|hash` hashed name, or an imported pattern list such as
        /// `*.corp,!dmz.corp`.
        public var hostPattern: String
        public var keyBlob: Data
        public var addedAt: Date
        public var revoked: Bool

        public init(hostPattern: String, key: SSHPublicKey, addedAt: Date = Date(), revoked: Bool = false) {
            self.hostPattern = hostPattern
            self.keyBlob = Data(key.blob)
            self.addedAt = addedAt
            self.revoked = revoked
        }

        public var key: SSHPublicKey? { try? SSHPublicKey(blob: Array(keyBlob)) }
    }

    public private(set) var entries: [Entry] = []

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// The name OpenSSH files a host under.
    public static func hostKeyName(host: String, port: Int) -> String {
        port == 22 ? host.lowercased() : "[\(host.lowercased())]:\(port)"
    }

    func entries(for host: String, port: Int) -> [Entry] {
        let name = Self.hostKeyName(host: host, port: port)
        return entries.filter { Self.patternMatches($0.hostPattern, name: name) }
    }

    public func verdict(host: String, port: Int, key: SSHPublicKey) -> HostKeyVerdict {
        let known = entries(for: host, port: port)
        if known.contains(where: { $0.revoked && $0.keyBlob == Data(key.blob) }) { return .revoked }
        let active = known.filter { !$0.revoked }
        if active.contains(where: { $0.keyBlob == Data(key.blob) }) { return .trusted }
        let keys = active.compactMap(\.key)
        if let previous = keys.first(where: { $0.algorithmName == key.algorithmName }) ?? keys.first {
            return .changed(previous: previous)
        }
        return .unknown
    }

    /// Trusts `key` for the host, replacing the host's own entries. Entries
    /// that cover other hosts too (wildcards, lists) are left alone.
    public mutating func trust(host: String, port: Int, key: SSHPublicKey, at date: Date = Date()) {
        let name = Self.hostKeyName(host: host, port: port)
        entries.removeAll { !$0.revoked && Self.isOwnEntry($0.hostPattern, name: name) }
        entries.append(Entry(hostPattern: name, key: key, addedAt: date))
    }

    /// Forgets the host's own entries; wildcards and lists stay.
    public mutating func forget(host: String, port: Int) {
        let name = Self.hostKeyName(host: host, port: port)
        entries.removeAll { !$0.revoked && Self.isOwnEntry($0.hostPattern, name: name) }
    }

    public mutating func remove(_ entry: Entry) {
        entries.removeAll { $0 == entry }
    }

    // MARK: known_hosts text

    /// Adds the entries of an OpenSSH `known_hosts` file. Returns how many
    /// keys were added; `@cert-authority` lines are skipped.
    @discardableResult
    public mutating func importOpenSSH(_ text: String, at date: Date = Date()) -> Int {
        var added = 0
        for rawLine in text.components(separatedBy: .newlines) {
            var fields = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let first = fields.first, !first.hasPrefix("#") else { continue }
            var revoked = false
            if first.hasPrefix("@") {
                guard first == "@revoked" else { continue }
                revoked = true
                fields.removeFirst()
            }
            guard fields.count >= 3, let blob = Base64.decode(fields[2]),
                  let key = try? SSHPublicKey(blob: blob), key.algorithmName == fields[1] else { continue }
            // The whole list stays one entry, so negations apply to it.
            let entry = Entry(hostPattern: fields[0], key: key, addedAt: date, revoked: revoked)
            if revoked {
                // Revoking a key that's trusted under the same pattern
                // replaces the trusted entry.
                entries.removeAll { !$0.revoked && $0.hostPattern == entry.hostPattern && $0.keyBlob == entry.keyBlob }
            }
            if !entries.contains(where: {
                $0.hostPattern == entry.hostPattern && $0.keyBlob == entry.keyBlob && $0.revoked == entry.revoked
            }) {
                entries.append(entry)
                added += 1
            }
        }
        return added
    }

    public func exportOpenSSH() -> String {
        entries.compactMap { entry in
            guard let key = entry.key else { return nil }
            return (entry.revoked ? "@revoked " : "") + "\(entry.hostPattern) \(key.openSSHString())"
        }.joined(separator: "\n") + (entries.isEmpty ? "" : "\n")
    }

    /// An entry for exactly this host: its plain name or its hash, not a
    /// wildcard or list that covers other hosts as well.
    static func isOwnEntry(_ pattern: String, name: String) -> Bool {
        pattern.hasPrefix("|1|") ? patternMatches(pattern, name: name) : pattern.lowercased() == name
    }

    /// Plain names, wildcards, lists with `!` negations, as OpenSSH, and
    /// `|1|salt|hash` hashes.
    static func patternMatches(_ pattern: String, name: String) -> Bool {
        if pattern.hasPrefix("|1|") {
            let parts = pattern.split(separator: "|", omittingEmptySubsequences: true)
            guard parts.count == 3, let salt = Base64.decode(parts[1]), let hash = Base64.decode(parts[2]) else {
                return false
            }
            let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Array(name.utf8), using: SymmetricKey(data: salt))
            return Array(mac) == hash
        }
        return SSHConfigParser.matches(name, patterns: pattern.split(separator: ",").map(String.init))
    }
}
