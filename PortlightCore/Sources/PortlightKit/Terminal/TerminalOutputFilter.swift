/// Sits between the server and the terminal emulator and removes the few
/// escape sequences a hostile server could abuse, passing everything else
/// through untouched:
/// - Kitty graphics (APC `G`): its file transmission modes let a server
///   probe which files exist in the app's container.
/// - Over-long OSC, DCS, APC, PM and SOS strings: the emulator buffers them
///   without a limit, so an endless one would exhaust memory. They're
///   dropped once past a cap, without buffering the rest.
/// - Title stack push and pop (CSI 22/23 t): the emulator's stack has no
///   depth limit.
/// It works on raw bytes across chunk boundaries, and tells 8-bit C1
/// introducers apart from bytes inside UTF-8 characters.
public final class TerminalOutputFilter {
    public static let maxOSC = 1 << 20
    public static let maxDCS = 16 << 20
    public static let maxOther = 64 << 10
    static let maxCSI = 256

    private enum Kind { case osc, dcs, apc, other }

    private enum State {
        case ground
        /// After ESC, waiting for the next byte.
        case escape
        case csi
        /// Inside a string sequence. `dropping` means it's being discarded
        /// (kitty graphics, or past the cap) and isn't buffered.
        case string(Kind, dropping: Bool)
    }

    private var state = State.ground
    /// Bytes held back: an escape sequence not yet complete.
    private var held: [UInt8] = []
    /// UTF-8 continuation bytes still expected in ground state.
    private var utf8Remaining = 0
    /// Payload bytes seen in the current string (whether or not buffered).
    private var stringLength = 0

    public init() {}

    /// Bytes held back for an unfinished sequence (for tests).
    public var bufferedCount: Int { held.count }

    public func process(_ input: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(input.count)
        for byte in input { step(byte, &out) }
        return out
    }

    private func step(_ byte: UInt8, _ out: inout [UInt8]) {
        switch state {
        case .ground:
            ground(byte, &out)

        case .escape:
            switch byte {
            case 0x5B:  // [
                held.append(byte)
                state = .csi
            case 0x5D: beginString(.osc, byte)  // ]
            case 0x50: beginString(.dcs, byte)  // P
            case 0x5F: beginString(.apc, byte)  // _
            case 0x5E, 0x58: beginString(.other, byte)  // ^ PM, X SOS
            case 0x1B:
                out += held
                held = [byte]
            default:
                out += held
                out.append(byte)
                held = []
                state = .ground
            }

        case .csi:
            switch byte {
            case 0x40...0x7E:  // final byte
                held.append(byte)
                if !isTitleStackOperation(held) { out += held }
                held = []
                state = .ground
            case 0x1B:
                out += held
                held = [byte]
                state = .escape
            case 0x18, 0x1A:  // CAN, SUB abort
                out += held
                out.append(byte)
                held = []
                state = .ground
            default:
                held.append(byte)
                if held.count > Self.maxCSI {
                    out += held
                    held = []
                    state = .ground
                }
            }

        case .string(let kind, let dropping):
            // Ends the way the emulator's string parser ends one: BEL (not
            // in DCS), ESC (ESC \ is ST), CAN or SUB. It doesn't stop at an
            // 8-bit ST, so neither does this, or a string could get past
            // the cap by hiding behind one.
            switch byte {
            case 0x07 where kind != .dcs:
                if !dropping {
                    out += held
                    out.append(byte)
                }
                held = []
                state = .ground
            case 0x1B:
                // ESC ends the string (ESC \ is ST); the emulator handles it.
                if !dropping { out += held }
                held = [byte]
                state = .escape
            case 0x18, 0x1A:
                if !dropping { out += held }
                out.append(byte)
                held = []
                state = .ground
            default:
                stringLength += 1
                if dropping { return }
                if kind == .apc, stringLength == 1, byte == 0x47 {  // G: kitty graphics
                    held = []
                    state = .string(kind, dropping: true)
                    return
                }
                if stringLength > cap(for: kind) {
                    held = []
                    state = .string(kind, dropping: true)
                    return
                }
                held.append(byte)
            }
        }
    }

    private func ground(_ byte: UInt8, _ out: inout [UInt8]) {
        if utf8Remaining > 0, (0x80...0xBF).contains(byte) {
            utf8Remaining -= 1
            out.append(byte)
            return
        }
        utf8Remaining = 0
        switch byte {
        case 0x1B:
            held = [byte]
            state = .escape
        case 0x9B:
            held = [byte]
            state = .csi
        case 0x9D: beginString(.osc, byte)
        case 0x90: beginString(.dcs, byte)
        case 0x9F: beginString(.apc, byte)
        case 0x98, 0x9E: beginString(.other, byte)
        case 0xC2...0xDF:
            utf8Remaining = 1
            out.append(byte)
        case 0xE0...0xEF:
            utf8Remaining = 2
            out.append(byte)
        case 0xF0...0xF4:
            utf8Remaining = 3
            out.append(byte)
        default:
            out.append(byte)
        }
    }

    private func beginString(_ kind: Kind, _ introducer: UInt8) {
        held.append(introducer)
        stringLength = 0
        state = .string(kind, dropping: false)
    }

    private func cap(for kind: Kind) -> Int {
        switch kind {
        case .osc, .apc: Self.maxOSC
        case .dcs: Self.maxDCS
        case .other: Self.maxOther
        }
    }

    /// CSI 22 … t and CSI 23 … t: push or pop the window title.
    private func isTitleStackOperation(_ sequence: [UInt8]) -> Bool {
        guard sequence.last == 0x74 else { return false }  // t
        let start = sequence.first == 0x9B ? 1 : 2
        guard sequence.count >= start + 3 else { return false }
        let params = sequence[start..<(sequence.count - 1)]
        let first = params.prefix { $0 != 0x3B }
        return first.elementsEqual([0x32, 0x32]) || first.elementsEqual([0x32, 0x33])
    }
}
