import Crypto
import Foundation

/// What to do with the key a server presented.
public enum HostKeyVerdict: Equatable, Sendable {
    /// Seen and trusted before.
    case trusted
    /// Never seen for this host: ask the user to compare the fingerprint.
    /// `otherTypesKnown` is set when keys of a different type are on file.
    case unknown(otherTypesKnown: Bool)
    /// A different key of the same type is on file: possibly an attack, or
    /// the server was rebuilt. Refuse unless the user deliberately replaces it.
    case changed(previous: SSHPublicKey)
    /// The key is marked revoked.
    case revoked
}

/// Trust-on-first-use host key records, compatible with OpenSSH
/// `known_hosts` for import and export (including hashed hostnames).
public struct KnownHosts: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Hashable, Sendable {
        /// `hostname` for port 22, `[hostname]:port` otherwise, or an
        /// OpenSSH `|1|salt|hash` hashed name.
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
        if let previous = active.compactMap(\.key).first(where: { $0.algorithmName == key.algorithmName }) {
            return .changed(previous: previous)
        }
        return .unknown(otherTypesKnown: !active.isEmpty)
    }

    /// Trusts `key` for the host, replacing any key of the same type.
    public mutating func trust(host: String, port: Int, key: SSHPublicKey, at date: Date = Date()) {
        let name = Self.hostKeyName(host: host, port: port)
        entries.removeAll { entry in
            !entry.revoked && Self.patternMatches(entry.hostPattern, name: name)
                && entry.key?.algorithmName == key.algorithmName
        }
        entries.append(Entry(hostPattern: name, key: key, addedAt: date))
    }

    public mutating func forget(host: String, port: Int) {
        let name = Self.hostKeyName(host: host, port: port)
        entries.removeAll { !$0.revoked && Self.patternMatches($0.hostPattern, name: name) }
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
            for pattern in fields[0].split(separator: ",") {
                let entry = Entry(hostPattern: String(pattern), key: key, addedAt: date, revoked: revoked)
                if !entries.contains(where: { $0.hostPattern == entry.hostPattern && $0.keyBlob == entry.keyBlob }) {
                    entries.append(entry)
                    added += 1
                }
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

    /// Plain names, wildcards, negation-free lists and `|1|salt|hash` hashes.
    static func patternMatches(_ pattern: String, name: String) -> Bool {
        if pattern.hasPrefix("|1|") {
            let parts = pattern.split(separator: "|", omittingEmptySubsequences: true)
            guard parts.count == 3, let salt = Base64.decode(parts[1]), let hash = Base64.decode(parts[2]) else {
                return false
            }
            let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Array(name.utf8), using: SymmetricKey(data: salt))
            return Array(mac) == hash
        }
        return SSHConfigParser.glob(pattern, name)
    }
}
