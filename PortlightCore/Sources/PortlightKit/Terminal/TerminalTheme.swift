import Foundation

/// An sRGB colour parsed from `#rrggbb`.
public struct RGB: Codable, Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    public var hex: String { String(format: "#%02x%02x%02x", red, green, blue) }

    /// Relative luminance (WCAG), 0 for black to 1 for white.
    public var luminance: Double {
        func channel(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio between two colours (1 to 21).
    public func contrast(with other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Colours for the terminal: foreground, background, cursor, selection and
/// the 16 ANSI colours (normal 0–7, bright 8–15).
public struct TerminalTheme: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var foreground: RGB
    public var background: RGB
    public var cursor: RGB
    public var selection: RGB
    public var ansi: [RGB]

    public var id: String { name }
    public var isDark: Bool { background.luminance < 0.4 }

    init(name: String, foreground: String, background: String, cursor: String, selection: String, ansi: [String]) {
        precondition(ansi.count == 16, "a theme needs 16 ANSI colours")
        self.name = name
        self.foreground = RGB(hex: foreground)!
        self.background = RGB(hex: background)!
        self.cursor = RGB(hex: cursor)!
        self.selection = RGB(hex: selection)!
        self.ansi = ansi.map { RGB(hex: $0)! }
    }

    public static let defaultName = "Portlight Night"

    public static func named(_ name: String) -> TerminalTheme {
        all.first { $0.name == name } ?? all[0]
    }

    public static let all: [TerminalTheme] = [
        TerminalTheme(
            name: "Portlight Night", foreground: "#d7dae0", background: "#101418", cursor: "#f5a524", selection: "#2c3540",
            ansi: ["#1d2128", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#abb2bf",
                   "#5c6370", "#ff7a85", "#b5e890", "#ffd68a", "#7cc4ff", "#dd9af0", "#7fd4e0", "#ffffff"]),
        TerminalTheme(
            name: "Paper", foreground: "#1f2328", background: "#ffffff", cursor: "#1f2328", selection: "#b4d5fe",
            ansi: ["#000000", "#c91b00", "#00a600", "#a5a200", "#0225c7", "#c930c7", "#00a6b2", "#bfbfbf",
                   "#686868", "#ff6e67", "#2bbf35", "#b3b000", "#6871ff", "#ff77ff", "#00b8c2", "#ffffff"]),
        TerminalTheme(
            name: "Solarized Dark", foreground: "#839496", background: "#002b36", cursor: "#93a1a1", selection: "#073642",
            ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                   "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]),
        TerminalTheme(
            name: "Solarized Light", foreground: "#657b83", background: "#fdf6e3", cursor: "#586e75", selection: "#eee8d5",
            ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                   "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]),
        TerminalTheme(
            name: "Dracula", foreground: "#f8f8f2", background: "#282a36", cursor: "#f8f8f2", selection: "#44475a",
            ansi: ["#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
                   "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff"]),
        TerminalTheme(
            name: "Nord", foreground: "#d8dee9", background: "#2e3440", cursor: "#d8dee9", selection: "#434c5e",
            ansi: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
                   "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"]),
        TerminalTheme(
            name: "Gruvbox Dark", foreground: "#ebdbb2", background: "#282828", cursor: "#ebdbb2", selection: "#504945",
            ansi: ["#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
                   "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"]),
    ]
}
