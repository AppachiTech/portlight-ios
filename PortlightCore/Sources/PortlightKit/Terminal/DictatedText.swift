import Foundation

/// Speech or edited text going into a terminal as if typed. It must never
/// run anything by itself, so line breaks become spaces and control
/// characters (Return, Ctrl-C, escape sequences) are dropped: the user
/// presses Return when they've read it.
public enum DictatedText {
    public static func bytes(for text: String) -> [UInt8] {
        var cleaned = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0A, 0x0D, 0x09, 0x0B, 0x0C, 0x85, 0x2028, 0x2029:
                cleaned.append(" ")
            case 0x00...0x1F, 0x7F...0x9F:
                continue
            default:
                cleaned.append(scalar)
            }
        }
        let collapsed = String(cleaned)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return Array(collapsed.utf8)
    }
}
