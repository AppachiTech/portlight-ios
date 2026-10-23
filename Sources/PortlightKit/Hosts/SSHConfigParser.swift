import Foundation

/// Reads an OpenSSH client config (`~/.ssh/config`) so existing hosts can be
/// imported. Follows ssh_config(5) where it matters for importing: keywords
/// are case-insensitive, `Host` patterns support `*`, `?` and `!`, and for
/// each setting the first value obtained wins.
public enum SSHConfigParser {
    public struct Entry: Equatable, Sendable {
        public var alias: String
        public var hostname: String
        public var user: String?
        public var port: Int?
        public var identityFile: String?
        public var proxyJump: String?
    }

    public struct Result: Equatable, Sendable {
        public var entries: [Entry]
        public var warnings: [String]
    }

    struct Block {
        var patterns: [String]  // empty for the implicit global block
        var settings: [(String, String)] = []
    }

    public static func parse(_ text: String) -> Result {
        var blocks = [Block(patterns: [])]
        var warnings: [String] = []
        var aliases: [String] = []
        var inMatch = false

        for (number, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let (keyword, value) = splitKeyword(line) else {
                warnings.append("Line \(number + 1): couldn't read \"\(line)\"")
                continue
            }
            switch keyword {
            case "host":
                inMatch = false
                let patterns = tokens(value)
                blocks.append(Block(patterns: patterns))
                for pattern in patterns where !isPattern(pattern) && !aliases.contains(pattern) {
                    aliases.append(pattern)
                }
            case "match":
                inMatch = true
                warnings.append("Line \(number + 1): Match blocks are skipped")
            case "include":
                warnings.append("Line \(number + 1): Include isn't followed; paste the included file too")
            default:
                if !inMatch { blocks[blocks.count - 1].settings.append((keyword, value)) }
            }
        }

        let entries = aliases.map { alias -> Entry in
            var found: [String: String] = [:]
            for block in blocks where block.patterns.isEmpty || matches(alias, patterns: block.patterns) {
                for (key, value) in block.settings where found[key] == nil {
                    found[key] = value
                }
            }
            var entry = Entry(alias: alias, hostname: alias)
            if let hostname = found["hostname"] {
                entry.hostname = hostname.replacingOccurrences(of: "%h", with: alias)
            }
            entry.user = found["user"]
            if let port = found["port"] {
                if let value = Int(port), (1...65535).contains(value) {
                    entry.port = value
                } else {
                    warnings.append("\(alias): ignoring port \(port)")
                }
            }
            entry.identityFile = found["identityfile"]
            if let jump = found["proxyjump"], jump.lowercased() != "none" {
                entry.proxyJump = jump.split(separator: ",").first.map(String.init)  // first hop only
            }
            return entry
        }
        return Result(entries: entries, warnings: warnings)
    }

    /// `Keyword value`, `Keyword=value` or `Keyword = value`, with quotes removed.
    static func splitKeyword(_ line: String) -> (String, String)? {
        guard let split = line.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "=" }) else { return nil }
        let keyword = line[..<split].lowercased()
        var value = line[split...].drop(while: { $0 == " " || $0 == "\t" })
        if value.first == "=" { value = value.dropFirst().drop(while: { $0 == " " || $0 == "\t" }) }
        var text = String(value).trimmingCharacters(in: .whitespaces)
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") { text = String(text.dropFirst().dropLast()) }
        guard !keyword.isEmpty, !text.isEmpty else { return nil }
        return (keyword, text)
    }

    static func tokens(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { $0.replacingOccurrences(of: "\"", with: "") }
    }

    static func isPattern(_ text: String) -> Bool {
        text.contains("*") || text.contains("?") || text.hasPrefix("!")
    }

    /// ssh_config pattern-list matching: any positive match and no negated match.
    static func matches(_ name: String, patterns: [String]) -> Bool {
        var matched = false
        for pattern in patterns {
            if pattern.hasPrefix("!") {
                if glob(String(pattern.dropFirst()), name) { return false }
            } else if glob(pattern, name) {
                matched = true
            }
        }
        return matched
    }

    /// `*` and `?` wildcards, case-insensitive like OpenSSH host matching.
    static func glob(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.lowercased())
        let t = Array(text.lowercased())
        var pi = 0, ti = 0
        var star = -1, mark = 0
        while ti < t.count {
            if pi < p.count, p[pi] == "?" || p[pi] == t[ti] {
                pi += 1
                ti += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi
                mark = ti
                pi += 1
            } else if star >= 0 {
                pi = star + 1
                mark += 1
                ti = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    /// Turns parsed entries into hosts, linking ProxyJump to hosts by alias
    /// (among the new entries or `existing`). Entries whose alias matches an
    /// existing host's label are skipped.
    public static func makeHosts(from entries: [Entry], existing: [Host] = [], defaultUser: String = "root") -> [Host] {
        let taken = Set(existing.map { $0.label.lowercased() })
        var created: [String: Host] = [:]
        var ordered: [Host] = []
        for entry in entries where !taken.contains(entry.alias.lowercased()) {
            var notes: [String] = []
            if let identity = entry.identityFile {
                notes.append("Imported from ssh config. IdentityFile was \(identity): import that key under Keys and pick it here.")
            }
            let host = Host(
                label: entry.alias, hostname: entry.hostname, port: entry.port ?? 22,
                username: entry.user ?? defaultUser, auth: .password, provider: guessProvider(entry.hostname),
                notes: notes.isEmpty ? nil : notes.joined(separator: "\n"))
            created[entry.alias.lowercased()] = host
            ordered.append(host)
        }
        let all = existing.reduce(into: created) { map, host in
            if map[host.label.lowercased()] == nil { map[host.label.lowercased()] = host }
        }
        return ordered.map { host in
            var host = host
            if let entry = entries.first(where: { $0.alias == host.label }), let jump = entry.proxyJump {
                let alias = jump.split(separator: "@").last.map { String($0.split(separator: ":").first ?? $0) } ?? jump
                host.jumpHostID = all[alias.lowercased()]?.id
                if host.jumpHostID == nil {
                    host.notes = [host.notes, "ProxyJump \(jump) isn't a saved host; add it and pick it as the jump host."]
                        .compactMap { $0 }.joined(separator: "\n")
                }
            }
            return host
        }
    }

    /// Recognises the providers' public DNS names.
    public static func guessProvider(_ hostname: String) -> CloudProvider {
        let name = hostname.lowercased()
        if name.hasSuffix(".amazonaws.com") { return .aws }
        if name.hasSuffix(".googleusercontent.com") || name.hasSuffix(".internal") && name.contains(".c.") { return .gcp }
        if name.hasSuffix(".cloudapp.azure.com") || name.hasSuffix(".cloudapp.net") { return .azure }
        if name.hasSuffix(".linodeusercontent.com") || name.hasSuffix(".members.linode.com") { return .linode }
        if name.hasSuffix(".your-server.de") { return .hetzner }
        if name.hasSuffix(".oraclecloud.com") { return .oracle }
        return .other
    }
}
