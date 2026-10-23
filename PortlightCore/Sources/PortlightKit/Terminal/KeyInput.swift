import Foundation

/// A key the on-screen key bar (or a hardware keyboard shortcut) can send.
public enum TerminalKey: Hashable, Codable, Sendable {
    case escape, tab, enter, backspace, delete, insert
    case up, down, left, right
    case home, end, pageUp, pageDown
    case function(Int)
    case text(String)
}

public struct KeyModifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shift = KeyModifiers(rawValue: 1)
    public static let alt = KeyModifiers(rawValue: 2)
    public static let ctrl = KeyModifiers(rawValue: 4)

    /// xterm's modifier parameter: 1 + shift + 2·alt + 4·ctrl.
    var xtermParameter: Int { 1 + rawValue }
}

/// Encodes keys as the bytes xterm (and `TERM=xterm-256color` programs)
/// expect.
public enum KeyEncoder {
    static let esc: UInt8 = 0x1B

    /// The control character for `character` (Ctrl-C → 0x03), or nil when
    /// the key has no control form.
    public static func control(_ character: Character) -> UInt8? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1, scalar.isASCII else {
            return nil
        }
        let value = UInt8(scalar.value)
        switch value {
        case 0x61...0x7A: return value - 0x60  // a-z
        case 0x40...0x5F: return value - 0x40  // @ A-Z [ \ ] ^ _
        case 0x20: return 0x00  // Ctrl-Space = NUL
        case 0x3F: return 0x7F  // Ctrl-? = DEL
        case 0x32: return 0x00  // Ctrl-2 = NUL
        case 0x33...0x37: return value - 0x18  // Ctrl-3..7 = ESC, FS, GS, RS, US
        case 0x38: return 0x7F  // Ctrl-8 = DEL
        case 0x2F: return 0x1F  // Ctrl-/ = US
        default: return nil
        }
    }

    public static func bytes(for key: TerminalKey, modifiers: KeyModifiers = [], applicationCursorKeys: Bool = false) -> [UInt8] {
        let csi: [UInt8] = [esc, 0x5B]  // ESC [
        let ss3: [UInt8] = [esc, 0x4F]  // ESC O
        let modified = !modifiers.isEmpty
        let altPrefix: [UInt8] = modifiers.contains(.alt) ? [esc] : []

        func cursor(_ final: Character) -> [UInt8] {
            let f = UInt8(final.asciiValue!)
            if modified { return csi + Array("1;\(modifiers.xtermParameter)".utf8) + [f] }
            return (applicationCursorKeys ? ss3 : csi) + [f]
        }
        func tilde(_ number: Int) -> [UInt8] {
            let params = modified ? "\(number);\(modifiers.xtermParameter)" : "\(number)"
            return csi + Array(params.utf8) + [0x7E]
        }

        switch key {
        case .escape: return altPrefix + [esc]
        case .tab: return modifiers.contains(.shift) ? csi + [0x5A] : altPrefix + [0x09]
        case .enter: return altPrefix + [0x0D]
        case .backspace: return altPrefix + [modifiers.contains(.ctrl) ? 0x08 : 0x7F]
        case .delete: return tilde(3)
        case .insert: return tilde(2)
        case .pageUp: return tilde(5)
        case .pageDown: return tilde(6)
        case .up: return cursor("A")
        case .down: return cursor("B")
        case .right: return cursor("C")
        case .left: return cursor("D")
        case .home: return cursor("H")
        case .end: return cursor("F")
        case .function(let n):
            switch n {
            case 1...4:
                let final = UInt8(0x50 + n - 1)  // P Q R S
                return modified ? csi + Array("1;\(modifiers.xtermParameter)".utf8) + [final] : ss3 + [final]
            case 5: return tilde(15)
            case 6...10: return tilde(n + 11)  // 17-21
            case 11, 12: return tilde(n + 12)  // 23, 24
            default: return []
            }
        case .text(let string):
            var out: [UInt8] = []
            for character in string {
                var chunk: [UInt8]
                if modifiers.contains(.ctrl), let control = control(character) {
                    chunk = [control]
                } else if modifiers.contains(.shift), character.isLetter {
                    chunk = Array(String(character).uppercased().utf8)
                } else {
                    chunk = Array(String(character).utf8)
                }
                if modifiers.contains(.alt) { chunk.insert(esc, at: 0) }
                out += chunk
            }
            return out
        }
    }
}

/// One button on the key bar above the keyboard.
public enum KeyBarItem: Hashable, Codable, Sendable, Identifiable {
    /// Sends a key.
    case key(TerminalKey)
    /// Sticky Ctrl: applies to the next key, double-tap to lock.
    case ctrl
    /// Sticky Alt/Meta.
    case alt
    /// Opens the saved-commands list.
    case snippets
    /// Shows or hides the software keyboard.
    case keyboard

    public var id: String {
        switch self {
        case .key(let key): "key-\(Self.label(for: key))"
        case .ctrl: "ctrl"
        case .alt: "alt"
        case .snippets: "snippets"
        case .keyboard: "keyboard"
        }
    }

    public var label: String {
        switch self {
        case .key(let key): Self.label(for: key)
        case .ctrl: "ctrl"
        case .alt: "alt"
        case .snippets: "{ }"
        case .keyboard: "⌨︎"
        }
    }

    static func label(for key: TerminalKey) -> String {
        switch key {
        case .escape: "esc"
        case .tab: "tab"
        case .enter: "⏎"
        case .backspace: "⌫"
        case .delete: "del"
        case .insert: "ins"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .home: "home"
        case .end: "end"
        case .pageUp: "pgup"
        case .pageDown: "pgdn"
        case .function(let n): "F\(n)"
        case .text(let text): text
        }
    }

    /// The default bar: the keys phones lack, then common shell symbols.
    public static let defaultLayout: [KeyBarItem] = [
        .key(.escape), .ctrl, .alt, .key(.tab),
        .key(.up), .key(.down), .key(.left), .key(.right),
        .key(.text("|")), .key(.text("~")), .key(.text("/")), .key(.text("-")),
        .key(.text("_")), .key(.text("*")), .key(.text("&")), .key(.text(";")),
        .key(.text("$")), .key(.text("<")), .key(.text(">")), .key(.text("`")),
        .key(.home), .key(.end), .key(.pageUp), .key(.pageDown),
        .key(.function(1)), .key(.function(2)), .key(.function(3)), .key(.function(4)),
        .key(.function(5)), .key(.function(6)), .key(.function(7)), .key(.function(8)),
        .key(.function(9)), .key(.function(10)), .key(.function(11)), .key(.function(12)),
        .snippets,
    ]
}

/// The sticky Ctrl/Alt state behind the key bar: tap once to apply to the
/// next key, tap twice to lock, tap again to release.
public struct StickyModifiers: Equatable, Sendable {
    public enum State: Equatable, Sendable { case off, once, locked }
    public var ctrl: State = .off
    public var alt: State = .off

    public init() {}

    public mutating func tap(_ modifier: KeyModifiers) {
        func next(_ state: State) -> State {
            switch state {
            case .off: .once
            case .once: .locked
            case .locked: .off
            }
        }
        if modifier == .ctrl { ctrl = next(ctrl) }
        if modifier == .alt { alt = next(alt) }
    }

    public var active: KeyModifiers {
        var m: KeyModifiers = []
        if ctrl != .off { m.insert(.ctrl) }
        if alt != .off { m.insert(.alt) }
        return m
    }

    /// Returns the modifiers for this key press and clears one-shot ones.
    public mutating func consume() -> KeyModifiers {
        let m = active
        if ctrl == .once { ctrl = .off }
        if alt == .once { alt = .off }
        return m
    }
}
