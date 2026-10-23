import Foundation

/// Errors raised while reading SSH wire-format data (RFC 4251 §5).
public enum SSHWireError: Error, Equatable, Sendable {
    case truncated
    case invalidUTF8
    case lengthTooLarge(Int)
}

/// Appends SSH wire-format values (RFC 4251 §5) to a byte array.
public struct SSHWriter: Sendable {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public mutating func writeUInt32(_ value: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value))
    }

    /// An SSH `string`: a uint32 length followed by the raw bytes.
    public mutating func writeString<B: Collection>(_ value: B) where B.Element == UInt8 {
        writeUInt32(UInt32(value.count))
        bytes.append(contentsOf: value)
    }

    public mutating func writeString(_ value: String) {
        writeString(Array(value.utf8))
    }

    /// An SSH `mpint` holding a non-negative big-endian magnitude: leading
    /// zero bytes are dropped, and a zero byte is prepended when the high bit
    /// is set so the value is not read as negative.
    public mutating func writeMPInt<B: Collection>(unsigned magnitude: B) where B.Element == UInt8 {
        var value = Array(magnitude.drop(while: { $0 == 0 }))
        if let first = value.first, first & 0x80 != 0 {
            value.insert(0, at: 0)
        }
        writeString(value)
    }

    /// Raw bytes with no length prefix.
    public mutating func writeRaw<B: Collection>(_ value: B) where B.Element == UInt8 {
        bytes.append(contentsOf: value)
    }
}

/// Reads SSH wire-format values from a byte array.
public struct SSHReader: Sendable {
    private let bytes: [UInt8]
    public private(set) var offset: Int = 0

    /// Upper bound for any single length field, to refuse absurd allocations
    /// from corrupt or hostile input.
    public static let maxFieldLength = 1 << 24

    public init<B: Collection>(_ bytes: B) where B.Element == UInt8 {
        self.bytes = Array(bytes)
    }

    public var remaining: Int { bytes.count - offset }
    public var isAtEnd: Bool { remaining == 0 }

    public mutating func readUInt32() throws -> UInt32 {
        guard remaining >= 4 else { throw SSHWireError.truncated }
        let value = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
        offset += 4
        return value
    }

    public mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, count <= Self.maxFieldLength else { throw SSHWireError.lengthTooLarge(count) }
        guard remaining >= count else { throw SSHWireError.truncated }
        let value = Array(bytes[offset..<offset + count])
        offset += count
        return value
    }

    public mutating func readString() throws -> [UInt8] {
        let length = Int(try readUInt32())
        return try readBytes(length)
    }

    public mutating func readUTF8String() throws -> String {
        let raw = try readString()
        guard let value = String(bytes: raw, encoding: .utf8) else { throw SSHWireError.invalidUTF8 }
        return value
    }

    /// An `mpint` returned as an unsigned big-endian magnitude without the
    /// sign-padding zero byte.
    public mutating func readMPIntMagnitude() throws -> [UInt8] {
        Array(try readString().drop(while: { $0 == 0 }))
    }

    public mutating func readRemaining() -> [UInt8] {
        let value = Array(bytes[offset...])
        offset = bytes.count
        return value
    }
}

extension Array where Element == UInt8 {
    /// Left-pads with zeros (or keeps the trailing bytes) to exactly `length`.
    func leftPadded(to length: Int) -> [UInt8] {
        if count == length { return self }
        if count > length { return Array(suffix(length)) }
        return [UInt8](repeating: 0, count: length - count) + self
    }
}

enum Base64 {
    /// Standard base64 decoding that tolerates whitespace and missing padding.
    static func decode(_ text: some StringProtocol) -> [UInt8]? {
        var cleaned = text.filter { !$0.isWhitespace }
        let remainder = cleaned.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 { cleaned += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: String(cleaned)).map(Array.init)
    }

    static func encode<B: Collection>(_ bytes: B) -> String where B.Element == UInt8 {
        Data(bytes).base64EncodedString()
    }
}
