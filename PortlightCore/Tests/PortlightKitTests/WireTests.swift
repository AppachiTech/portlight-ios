import Testing
@testable import PortlightKit

@Suite struct WireTests {
    @Test func roundTripsAllFieldTypes() throws {
        var writer = SSHWriter()
        writer.writeUInt32(0xDEADBEEF)
        writer.writeString("ssh-ed25519")
        writer.writeMPInt(unsigned: [0x00, 0x00, 0x80, 0x01])  // leading zeros dropped, sign byte added
        writer.writeMPInt(unsigned: [0x7F])
        var reader = SSHReader(writer.bytes)
        #expect(try reader.readUInt32() == 0xDEADBEEF)
        #expect(try reader.readUTF8String() == "ssh-ed25519")
        #expect(try reader.readString() == [0x00, 0x80, 0x01])
        #expect(try reader.readString() == [0x7F])
        #expect(reader.isAtEnd)
    }

    @Test func mpintMagnitudeStripsSignByte() throws {
        var writer = SSHWriter()
        writer.writeMPInt(unsigned: [0xFF, 0xEE])
        var reader = SSHReader(writer.bytes)
        #expect(try reader.readMPIntMagnitude() == [0xFF, 0xEE])
    }

    @Test func truncatedInputThrows() {
        var reader = SSHReader([0, 0, 0, 9, 1, 2])
        #expect(throws: SSHWireError.truncated) { try reader.readString() }
    }

    @Test func refusesHugeLengths() {
        var reader = SSHReader([0x7F, 0xFF, 0xFF, 0xFF])
        #expect(throws: SSHWireError.lengthTooLarge(0x7FFF_FFFF)) { try reader.readString() }
    }

    @Test func base64ToleratesWhitespaceAndMissingPadding() {
        #expect(Base64.decode("aGVs\nbG8") == Array("hello".utf8))
        #expect(Base64.decode("a") == nil)
    }

    @Test func leftPadding() {
        #expect([1, 2].leftPadded(to: 4) == [0, 0, 1, 2])
        #expect([1, 2, 3].leftPadded(to: 2) == [2, 3])
    }
}
