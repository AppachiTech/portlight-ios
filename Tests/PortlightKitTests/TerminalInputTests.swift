import Foundation
import Testing
@testable import PortlightKit

@Suite struct KeyEncoderTests {
    func s(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\u{1B}", with: "^[") }

    @Test func controlCharacters() {
        #expect(KeyEncoder.control("c") == 0x03)
        #expect(KeyEncoder.control("C") == 0x03)
        #expect(KeyEncoder.control("@") == 0x00)
        #expect(KeyEncoder.control("[") == 0x1B)
        #expect(KeyEncoder.control("\\") == 0x1C)
        #expect(KeyEncoder.control("]") == 0x1D)
        #expect(KeyEncoder.control("_") == 0x1F)
        #expect(KeyEncoder.control("?") == 0x7F)
        #expect(KeyEncoder.control(" ") == 0x00)
        #expect(KeyEncoder.control("é") == nil)
        #expect(KeyEncoder.control("1") == nil)
    }

    @Test func cursorKeysFollowApplicationMode() {
        #expect(s(KeyEncoder.bytes(for: .up)) == "^[[A")
        #expect(s(KeyEncoder.bytes(for: .up, applicationCursorKeys: true)) == "^[OA")
        #expect(s(KeyEncoder.bytes(for: .left, modifiers: .ctrl, applicationCursorKeys: true)) == "^[[1;5D")
        #expect(s(KeyEncoder.bytes(for: .right, modifiers: [.alt, .shift])) == "^[[1;4C")
        #expect(s(KeyEncoder.bytes(for: .home)) == "^[[H")
        #expect(s(KeyEncoder.bytes(for: .end, applicationCursorKeys: true)) == "^[OF")
    }

    @Test func editingAndFunctionKeys() {
        #expect(s(KeyEncoder.bytes(for: .delete)) == "^[[3~")
        #expect(s(KeyEncoder.bytes(for: .pageUp)) == "^[[5~")
        #expect(s(KeyEncoder.bytes(for: .pageDown, modifiers: .shift)) == "^[[6;2~")
        #expect(s(KeyEncoder.bytes(for: .function(1))) == "^[OP")
        #expect(s(KeyEncoder.bytes(for: .function(4), modifiers: .ctrl)) == "^[[1;5S")
        #expect(s(KeyEncoder.bytes(for: .function(5))) == "^[[15~")
        #expect(s(KeyEncoder.bytes(for: .function(6))) == "^[[17~")
        #expect(s(KeyEncoder.bytes(for: .function(10))) == "^[[21~")
        #expect(s(KeyEncoder.bytes(for: .function(11))) == "^[[23~")
        #expect(s(KeyEncoder.bytes(for: .function(12), modifiers: .alt)) == "^[[24;3~")
        #expect(KeyEncoder.bytes(for: .function(13)).isEmpty)
    }

    @Test func simpleKeysAndText() {
        #expect(KeyEncoder.bytes(for: .escape) == [0x1B])
        #expect(KeyEncoder.bytes(for: .tab) == [0x09])
        #expect(s(KeyEncoder.bytes(for: .tab, modifiers: .shift)) == "^[[Z")
        #expect(KeyEncoder.bytes(for: .enter) == [0x0D])
        #expect(KeyEncoder.bytes(for: .backspace) == [0x7F])
        #expect(KeyEncoder.bytes(for: .backspace, modifiers: .ctrl) == [0x08])
        #expect(KeyEncoder.bytes(for: .text("c"), modifiers: .ctrl) == [0x03])
        #expect(s(KeyEncoder.bytes(for: .text("b"), modifiers: .alt)) == "^[b")
        #expect(KeyEncoder.bytes(for: .text("x"), modifiers: [.ctrl, .alt]) == [0x1B, 0x18])
        #expect(KeyEncoder.bytes(for: .text("ä")) == Array("ä".utf8))
        #expect(KeyEncoder.bytes(for: .text("a"), modifiers: .shift) == Array("A".utf8))
    }

    @Test func stickyModifiersCycle() {
        var sticky = StickyModifiers()
        sticky.tap(.ctrl)
        #expect(sticky.ctrl == .once && sticky.active == .ctrl)
        #expect(sticky.consume() == .ctrl)
        #expect(sticky.ctrl == .off)

        sticky.tap(.ctrl)
        sticky.tap(.ctrl)
        #expect(sticky.ctrl == .locked)
        sticky.tap(.alt)
        #expect(sticky.consume() == [.ctrl, .alt])
        #expect(sticky.ctrl == .locked && sticky.alt == .off)
        sticky.tap(.ctrl)
        #expect(sticky.ctrl == .off)
    }

    @Test func keyBarLayoutIsUniqueAndCodable() throws {
        let ids = KeyBarItem.defaultLayout.map(\.id)
        #expect(Set(ids).count == ids.count)
        let data = try JSONEncoder().encode(KeyBarItem.defaultLayout)
        #expect(try JSONDecoder().decode([KeyBarItem].self, from: data) == KeyBarItem.defaultLayout)
    }
}

@Suite struct ThemeAndSettingsTests {
    @Test func themesAreReadable() {
        #expect(TerminalTheme.all.count >= 6)
        #expect(Set(TerminalTheme.all.map(\.name)).count == TerminalTheme.all.count)
        for theme in TerminalTheme.all {
            #expect(theme.ansi.count == 16)
            // 4.0 rather than WCAG's 4.5 because Solarized Light's published
            // palette is 4.1 by design; every other theme clears 4.5.
            #expect(theme.foreground.contrast(with: theme.background) >= 4.0, "\(theme.name) text contrast")
        }
        #expect(TerminalTheme.named("nope").name == TerminalTheme.defaultName)
        #expect(TerminalTheme.named("Paper").isDark == false)
        #expect(TerminalTheme.named("Dracula").isDark)
    }

    @Test func rgbParsing() {
        #expect(RGB(hex: "#ff8000") == RGB(red: 255, green: 128, blue: 0))
        #expect(RGB(hex: "00ff00")?.hex == "#00ff00")
        #expect(RGB(hex: "#fff") == nil)
        #expect(RGB(hex: "zzzzzz") == nil)
        #expect(abs(RGB(hex: "#000000")!.contrast(with: RGB(hex: "#ffffff")!) - 21) < 0.01)
    }

    @Test func settingsDecodeWithDefaultsAndClamp() throws {
        let partial = #"{"themeName":"Nord","fontSize":99,"cursorStyle":"triangle"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(partial.utf8))
        #expect(settings.themeName == "Nord")
        #expect(settings.fontSize == AppSettings.fontSizeRange.upperBound)
        #expect(settings.cursorStyle == .block)
        #expect(settings.keyBar == KeyBarItem.defaultLayout)
        #expect(settings.keepAliveInterval == 30)
    }

    @Test func snippetPayload() {
        #expect(Snippet(title: "t", command: "ls").payload == Array("ls\r".utf8))
        #expect(Snippet(title: "t", command: "ls", runImmediately: false).payload == Array("ls".utf8))
    }
}
