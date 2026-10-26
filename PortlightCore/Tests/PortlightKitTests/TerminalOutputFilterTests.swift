import Testing
@testable import PortlightKit

@Suite struct TerminalOutputFilterTests {
    func run(_ chunks: [String]) -> String {
        let filter = TerminalOutputFilter()
        var out: [UInt8] = []
        for chunk in chunks { out += filter.process(Array(chunk.utf8)) }
        return String(decoding: out, as: UTF8.self)
    }

    func runBytes(_ chunks: [[UInt8]]) -> [UInt8] {
        let filter = TerminalOutputFilter()
        return chunks.flatMap { filter.process($0) }
    }

    @Test func ordinaryOutputPassesUnchanged() {
        let text = "ls -la\r\n\u{1B}[1;32mgreen\u{1B}[0m café Û → 日本 🙂\r\n\u{1B}]0;title\u{07}\u{1B}]2;t2\u{1B}\\\u{1B}[?2004h\u{1B}(B\u{1B}7\u{1B}8"
        #expect(run([text]) == text)
        // The same, split at every byte boundary.
        let bytes = Array(text.utf8)
        for cut in 1..<bytes.count {
            #expect(runBytes([Array(bytes[..<cut]), Array(bytes[cut...])]) == bytes, "cut at \(cut)")
        }
    }

    @Test func kittyGraphicsAreDropped() {
        let out = run(["a\u{1B}_Gf=100,t=f;L2V0Yy9wYXNzd2Q=\u{1B}\\b"])
        #expect(!out.contains("_G"))
        #expect(!out.contains("L2V0Yy9wYXNzd2Q="))
        #expect(out.hasPrefix("a") && out.hasSuffix("b"))
        // Split across chunks too.
        let split = run(["x\u{1B}", "_", "Gt=f;cGF0aA==", "\u{1B}\\y"])
        #expect(!split.contains("_G") && !split.contains("cGF0aA=="))
        // Other APC strings still pass.
        #expect(run(["\u{1B}_other\u{1B}\\"]) == "\u{1B}_other\u{1B}\\")
    }

    @Test func oversizedStringsAreDroppedWithoutBuffering() {
        let filter = TerminalOutputFilter()
        var out = filter.process(Array("\u{1B}]52;c;".utf8))
        let block = [UInt8](repeating: 0x41, count: 64 * 1024)
        for _ in 0..<64 {  // 4 MiB, no terminator yet
            out += filter.process(block)
            #expect(filter.bufferedCount <= TerminalOutputFilter.maxOSC)
        }
        out += filter.process(Array("\u{07}after".utf8))
        let text = String(decoding: out, as: UTF8.self)
        #expect(!text.contains("AAAA"))
        #expect(text.hasSuffix("after"))
        // A normal-sized OSC 52 (clipboard) still goes through.
        let small = "\u{1B}]52;c;aGVsbG8=\u{07}"
        #expect(run([small]) == small)
    }

    @Test func titleStackPushAndPopAreDropped() {
        #expect(run(["a\u{1B}[22;0tb\u{1B}[23;0tc\u{1B}[22td\u{1B}[23t"]) == "abcd")
        // Other window ops pass.
        #expect(run(["\u{1B}[8;24;80t"]) == "\u{1B}[8;24;80t")
        #expect(run(["\u{1B}[2", "2", ";2t!"]) == "!")
    }

    @Test func eightBitIntroducersAreHandledButUTF8IsNot() {
        // 0x9F (8-bit APC) followed by G: kitty, dropped.
        let kitty = runBytes([[0x61, 0x9F] + Array("Gt=f;eA==".utf8) + [0x07, 0x62]])
        #expect(kitty == [0x61, 0x62])
        // The same byte inside a UTF-8 character is text: "Ÿ" is C5 B8,
        // "ğ" is C4 9F.
        let text: [UInt8] = Array("ğG ok".utf8)
        #expect(runBytes([text]) == text)
    }

    @Test func anEightBitTerminatorDoesNotEscapeTheCap() {
        // The emulator keeps reading past 0x9C inside a string, so the
        // filter must too: a payload after it is still capped.
        let filter = TerminalOutputFilter()
        _ = filter.process([0x1B, 0x5D, 0x30, 0x3B, 0x9C])
        let block = [UInt8](repeating: 0x41, count: 64 * 1024)
        var out: [UInt8] = []
        for _ in 0..<32 { out += filter.process(block) }
        #expect(out.isEmpty)
        #expect(filter.bufferedCount <= TerminalOutputFilter.maxOSC)
    }

    @Test func cancelledStringsResumeNormalOutput() {
        #expect(run(["\u{1B}]0;never\u{18}next"]) == "\u{1B}]0;never\u{18}next")
    }
}
