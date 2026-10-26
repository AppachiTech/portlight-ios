import Foundation
import Testing
@testable import PortlightKit

@Suite struct TerminalLayoutTests {
    @Test func newSettingsHaveDefaults() throws {
        let settings = AppSettings()
        #expect(settings.voiceInput)
        #expect(settings.terminalOrientation == .automatic)

        // Settings files written before these fields existed still load.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"themeName":"Nord"}"#.utf8))
        #expect(old.voiceInput && old.terminalOrientation == .automatic)
    }

    @Test func unknownLayoutAndOrientationFallBack() throws {
        let json = #"{"voiceInputLayout":"floating","terminalOrientation":"sideways","voiceInput":false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.terminalOrientation == .automatic)
        #expect(settings.voiceInput == false)
    }

    @Test func layoutSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.voiceInput = false
        settings.terminalOrientation = .landscape
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func fontSizeStepsAndClamps() {
        #expect(AppSettings.fontSize(13, steppedBy: 1) == 14)
        #expect(AppSettings.fontSize(13, steppedBy: -1) == 12)
        #expect(AppSettings.fontSize(28, steppedBy: 1) == 28)
        #expect(AppSettings.fontSize(8, steppedBy: -1) == 8)
        // Pinch can leave fractional sizes; steps land on whole points.
        #expect(AppSettings.fontSize(13.4, steppedBy: 1) == 14)
        #expect(AppSettings.fontSize(13.4, steppedBy: -1) == 13)
    }

    @Test func fontSizeToFitColumns() {
        // A monospaced glyph is about 0.6 pt wide per point of font size.
        #expect(AppSettings.fontSize(fitting: 80, inWidth: 844, advancePerPoint: 0.6) == 17)
        #expect(AppSettings.fontSize(fitting: 80, inWidth: 390, advancePerPoint: 0.6) == 8)
        #expect(AppSettings.fontSize(fitting: 80, inWidth: 200, advancePerPoint: 0.6) == 8)
        #expect(AppSettings.fontSize(fitting: 20, inWidth: 2000, advancePerPoint: 0.6) == 28)
        #expect(AppSettings.fontSize(fitting: 0, inWidth: 390, advancePerPoint: 0.6) == nil)
        #expect(AppSettings.fontSize(fitting: 80, inWidth: 390, advancePerPoint: 0) == nil)
    }

    @Test func dictatedTextNeverPressesReturn() {
        #expect(DictatedText.bytes(for: "list the files") == Array("list the files".utf8))
        #expect(DictatedText.bytes(for: "first line\nsecond line\r\n") == Array("first line second line".utf8))
        #expect(DictatedText.bytes(for: "a\rb\tc") == Array("a b c".utf8))
        #expect(!DictatedText.bytes(for: "x\ny\rz").contains(0x0D))
        #expect(!DictatedText.bytes(for: "x\ny\rz").contains(0x0A))
    }

    @Test func dictatedTextDropsControlCharacters() {
        #expect(DictatedText.bytes(for: "a\u{1B}[31mb") == Array("a[31mb".utf8))
        #expect(DictatedText.bytes(for: "a\u{03}b\u{7F}c\u{9B}d") == Array("abcd".utf8))
        #expect(DictatedText.bytes(for: "  padded  ") == Array("padded".utf8))
        #expect(DictatedText.bytes(for: "café → ok") == Array("café → ok".utf8))
        #expect(DictatedText.bytes(for: "\n\n").isEmpty)
    }
}

@Suite struct SavedCommandInputTests {
    @Test func savedCommandsAreTypedNotRunByDefault() throws {
        #expect(AppSettings().runSavedCommands == false)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"themeName":"Nord"}"#.utf8))
        #expect(old.runSavedCommands == false)
        var on = AppSettings()
        on.runSavedCommands = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on)).runSavedCommands)
    }

    @Test func inputPressesReturnOnlyWhenAllowedAndWanted() {
        let status = Snippet(title: "s", command: "git status")
        #expect(status.input(allowRun: false) == SavedCommandInput(text: "git status", pressReturn: false))
        #expect(status.input(allowRun: true) == SavedCommandInput(text: "git status", pressReturn: true))
        let apply = Snippet(title: "a", command: "terraform apply", runImmediately: false)
        #expect(apply.input(allowRun: true).pressReturn == false)
    }

    @Test func trailingLineBreaksAreNotTyped() {
        // A stored trailing newline would otherwise run the command.
        let snippet = Snippet(title: "s", command: "ls -la\n\r\n")
        #expect(snippet.input(allowRun: false).text == "ls -la")
        #expect(Snippet(title: "m", command: "cd /srv\nls\n").input(allowRun: false).text == "cd /srv\nls")
    }
}
