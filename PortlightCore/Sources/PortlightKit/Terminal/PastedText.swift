/// Text going into a terminal as a paste: from the clipboard, or a saved
/// command typed without running it. A paste may come from anywhere (a
/// web page, or a server through OSC 52), so it's cleaned first.
public enum PastedText {
    /// Drops escape and other control characters, keeping tabs and line
    /// breaks. ESC matters most: "ESC[201~" inside a paste would end a
    /// bracketed paste early, and the shell would run what follows.
    public static func cleaned(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A, 0x0D:
                kept.append(scalar)
            case 0x00...0x1F, 0x7F...0x9F:
                continue
            default:
                kept.append(scalar)
            }
        }
        return String(kept)
    }

    /// True when pasting would press Return. Checks scalars, because Swift
    /// treats "\r\n" as a single Character that contains("\n") misses.
    public static func hasLineBreak(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0 == "\n" || $0 == "\r" }
    }

    /// The cleaned text's bytes, inside bracketed-paste markers when the
    /// program asked for them.
    public static func bytes(for text: String, bracketed: Bool) -> [UInt8] {
        let body = Array(cleaned(text).utf8)
        guard !body.isEmpty else { return [] }
        guard bracketed else { return body }
        return [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E] + body + [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]
    }
}
