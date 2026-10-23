import Foundation

public enum CursorStyle: String, Codable, CaseIterable, Sendable {
    case block, underline, bar
}

/// User preferences. Decoding fills in defaults for anything missing, so
/// older settings files keep loading as fields are added.
public struct AppSettings: Codable, Equatable, Sendable {
    public var themeName: String = TerminalTheme.defaultName
    public var fontSize: Double = 13
    public var cursorStyle: CursorStyle = .block
    public var cursorBlink: Bool = true
    public var keepScreenAwake: Bool = true
    /// How long the app may sit in the background before it locks again.
    /// Unlocking (Face ID, Touch ID or the passcode) is always required;
    /// this only allows a short grace period, capped at five minutes.
    public var lockGracePeriod: Int = 0
    public var hapticBell: Bool = true
    public var scrollbackLines: Int = 5000
    public var keyBar: [KeyBarItem] = KeyBarItem.defaultLayout
    /// Seconds between keepalive probes on idle connections; 0 disables.
    public var keepAliveInterval: Int = 30

    public static let fontSizeRange: ClosedRange<Double> = 8...28

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        themeName = try c.decodeIfPresent(String.self, forKey: .themeName) ?? d.themeName
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        cursorStyle = (try? c.decodeIfPresent(CursorStyle.self, forKey: .cursorStyle)) ?? d.cursorStyle
        cursorBlink = try c.decodeIfPresent(Bool.self, forKey: .cursorBlink) ?? d.cursorBlink
        keepScreenAwake = try c.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? d.keepScreenAwake
        lockGracePeriod = try c.decodeIfPresent(Int.self, forKey: .lockGracePeriod) ?? d.lockGracePeriod
        lockGracePeriod = AppLockPolicy.allowedGracePeriods.contains(lockGracePeriod) ? lockGracePeriod : 0
        hapticBell = try c.decodeIfPresent(Bool.self, forKey: .hapticBell) ?? d.hapticBell
        scrollbackLines = try c.decodeIfPresent(Int.self, forKey: .scrollbackLines) ?? d.scrollbackLines
        keyBar = (try? c.decodeIfPresent([KeyBarItem].self, forKey: .keyBar)) ?? d.keyBar
        keepAliveInterval = try c.decodeIfPresent(Int.self, forKey: .keepAliveInterval) ?? d.keepAliveInterval
        fontSize = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
    }
}

/// A saved command for the key bar's snippets list.
public struct Snippet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var command: String
    /// Press return after typing it.
    public var runImmediately: Bool

    public init(id: UUID = UUID(), title: String, command: String, runImmediately: Bool = true) {
        self.id = id
        self.title = title
        self.command = command
        self.runImmediately = runImmediately
    }

    /// The bytes to send to the shell.
    public var payload: [UInt8] {
        Array(command.utf8) + (runImmediately ? [0x0D] : [])
    }

    public static let starters: [Snippet] = [
        Snippet(title: "tmux: attach or start", command: "tmux new -A -s main"),
        Snippet(title: "Disk usage", command: "df -h"),
        Snippet(title: "Memory", command: "free -h"),
        Snippet(title: "Top processes", command: "top"),
        Snippet(title: "Follow syslog", command: "sudo journalctl -f"),
    ]
}
