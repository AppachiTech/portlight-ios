import Testing
@testable import PortlightKit

/// Reference values computed with pyca/bcrypt's `bcrypt.kdf`, an independent
/// implementation of OpenBSD's bcrypt_pbkdf.
@Suite struct BcryptPBKDFTests {
    @Test(arguments: [
        ("password", [UInt8]("salt".utf8), 32, 4, "5bbf0cc293587f1c3635555c27796598d47e579071bf427e9d8fbe842aba34d9"),
        ("password", [UInt8](repeating: 0, count: 16), 48, 16,
         "d5a5cbccc68dd2599ba9f56817d414c00d7ef81f37ebc44d5d626e82937aa1223c94b683f3ec30383f8de79dd023e059"),
        ("correct horse", [UInt8]("0123456789abcdef".utf8), 24, 2, "d39618c69967a7b8a29f592af8b44ae04b2676d76ef0ed98"),
    ])
    func matchesReference(password: String, salt: [UInt8], length: Int, rounds: Int, expected: String) throws {
        let key = try BcryptPBKDF.derive(password: Array(password.utf8), salt: salt, keyLength: length, rounds: rounds)
        #expect(hex(key) == expected)
    }

    @Test func nonASCIIPasswordBytes() throws {
        let key = try BcryptPBKDF.derive(password: [0x00], salt: [0x01], keyLength: 64, rounds: 1)
        #expect(hex(key) == "65f54437cb9460b403b22b194b21c89df4dafe6858de05fef0ad34a02753ce19457bcb4e543cd37d80fd52731c2814221bd0459ec2be74a6b3af93f667380bda")
    }

    @Test func rejectsBadParameters() {
        #expect(throws: BcryptPBKDF.Error.invalidParameters) {
            try BcryptPBKDF.derive(password: [1], salt: [], keyLength: 32, rounds: 4)
        }
        #expect(throws: BcryptPBKDF.Error.invalidParameters) {
            try BcryptPBKDF.derive(password: [1], salt: [1], keyLength: 32, rounds: 0)
        }
    }
}
