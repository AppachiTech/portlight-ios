import Foundation

/// How to prove who you are to a host.
public enum AuthMethod: Codable, Hashable, Sendable {
    /// A password, kept in the Keychain under the host's id (or asked for
    /// each time when none is saved).
    case password
    /// A key from the key list.
    case key(UUID)

    public var keyID: UUID? {
        if case .key(let id) = self { return id }
        return nil
    }
}

/// A saved server.
public struct SSHHost: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var label: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var auth: AuthMethod
    public var provider: CloudProvider
    /// Optional folder name for grouping in the list.
    public var group: String?
    /// Another saved host to tunnel through (a bastion), like ProxyJump.
    public var jumpHostID: UUID?
    /// Typed into the shell once it starts, e.g. `tmux new -A -s main`.
    public var startupCommand: String?
    public var notes: String?
    public var createdAt: Date
    public var lastConnectedAt: Date?

    public init(
        id: UUID = UUID(), label: String = "", hostname: String, port: Int = 22, username: String,
        auth: AuthMethod = .password, provider: CloudProvider = .other, group: String? = nil,
        jumpHostID: UUID? = nil, startupCommand: String? = nil, notes: String? = nil,
        createdAt: Date = Date(), lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.hostname = hostname
        self.port = port
        self.username = username
        self.auth = auth
        self.provider = provider
        self.group = group
        self.jumpHostID = jumpHostID
        self.startupCommand = startupCommand
        self.notes = notes
        self.createdAt = createdAt
        self.lastConnectedAt = lastConnectedAt
    }

    /// What lists show: the label, or `user@host` when there is none.
    public var displayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? address : trimmed
    }

    /// `user@host` or `user@host:port`, with IPv6 literals bracketed.
    public var address: String {
        let host = hostname.contains(":") ? "[\(hostname)]" : hostname
        return port == 22 ? "\(username)@\(host)" : "\(username)@\(host):\(port)"
    }

    /// The problems that would stop a connection, empty when it's fine.
    public func validate() -> [HostValidationError] {
        var problems: [HostValidationError] = []
        let host = hostname.trimmingCharacters(in: .whitespaces)
        if host.isEmpty {
            problems.append(.missingHostname)
        } else if host.contains(where: { $0.isWhitespace || $0 == "@" || $0 == "/" }) {
            problems.append(.invalidHostname)
        }
        if !(1...65535).contains(port) { problems.append(.invalidPort) }
        if username.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append(.missingUsername)
        } else if username.contains(where: { $0.isWhitespace || $0 == "@" || $0 == ":" }) {
            problems.append(.invalidUsername)
        }
        return problems
    }
}

public enum HostValidationError: Error, Equatable, Sendable, LocalizedError {
    case missingHostname, invalidHostname, invalidPort, missingUsername, invalidUsername

    public var errorDescription: String? {
        switch self {
        case .missingHostname: "Enter a hostname or IP address."
        case .invalidHostname: "The hostname can't contain spaces, @ or /."
        case .invalidPort: "The port must be between 1 and 65535."
        case .missingUsername: "Enter the username to log in as."
        case .invalidUsername: "The username can't contain spaces, @ or :."
        }
    }
}

/// Parses quick-connect text such as `ubuntu@1.2.3.4`, `root@box:2222`,
/// `me@[2001:db8::1]:22` or `ssh -p 2222 me@box`.
public enum QuickConnect {
    public struct Target: Equatable, Sendable {
        public var username: String?
        public var hostname: String
        public var port: Int
    }

    public static func parse(_ text: String) -> Target? {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }
        if tokens.first == "ssh" { tokens.removeFirst() }
        var port: Int?
        var user: String?
        var destination: String?
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "-p", index + 1 < tokens.count {
                port = Int(tokens[index + 1])
                guard port != nil else { return nil }
                index += 2
                continue
            }
            if token == "-l", index + 1 < tokens.count {
                user = tokens[index + 1]
                index += 2
                continue
            }
            if token.hasPrefix("-") {
                // ssh options that take a value: skip the value too.
                let takesValue = Set("BbcDEeFIiJLlmOoQRSWw")
                if token.count == 2, let flag = token.last, takesValue.contains(flag) {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            guard destination == nil else { return nil }
            destination = token
            index += 1
        }
        guard var rest = destination else { return nil }
        if rest.hasPrefix("ssh://") { rest.removeFirst("ssh://".count) }
        if let at = rest.lastIndex(of: "@") {
            user = String(rest[..<at])
            rest = String(rest[rest.index(after: at)...])
        }
        var host = rest
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            host = String(rest[rest.index(after: rest.startIndex)..<close])
            let after = rest[rest.index(after: close)...]
            if after.hasPrefix(":") {
                guard let value = Int(after.dropFirst()) else { return nil }
                port = value
            } else if !after.isEmpty {
                return nil
            }
        } else if rest.filter({ $0 == ":" }).count == 1, let colon = rest.firstIndex(of: ":") {
            host = String(rest[..<colon])
            guard let value = Int(rest[rest.index(after: colon)...]) else { return nil }
            port = value
        }
        guard !host.isEmpty, (1...65535).contains(port ?? 22) else { return nil }
        if let u = user, u.isEmpty { user = nil }
        return Target(username: user, hostname: host, port: port ?? 22)
    }
}
