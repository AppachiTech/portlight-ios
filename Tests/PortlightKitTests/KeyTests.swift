import Foundation
import Testing
@testable import PortlightKit

@Suite struct KeyImportTests {
    typealias F = KeyFixtures

    @Test(arguments: [
        (F.ed25519Plain, F.ed25519PlainFingerprint, KeyAlgorithm.ed25519, "portlight-test-ed25519_plain"),
        (F.p256Plain, F.p256PlainFingerprint, .ecdsaP256, "portlight-test-p256_plain"),
    ])
    func importsUnencryptedOpenSSHKeys(text: String, fingerprint: String, algorithm: KeyAlgorithm, comment: String) throws {
        #expect(KeyImporter.inspect(text) == .openSSH(encrypted: false))
        let imported = try KeyImporter.importKey(text)
        #expect(imported.key.algorithm == algorithm)
        #expect(imported.key.publicKey.sha256Fingerprint == fingerprint)
        #expect(imported.comment == comment)
    }

    @Test(arguments: [
        (F.ed25519Enc, F.ed25519EncFingerprint),
        (F.ed25519Enc16, F.ed25519Enc16Fingerprint),
        (F.p384Enc, F.p384EncFingerprint),
        (F.p521Enc, F.p521EncFingerprint),
        (F.ed25519Aes128ctr, F.ed25519Aes128ctrFingerprint),
        (F.ed25519Aes256cbc, F.ed25519Aes256cbcFingerprint),
        (F.ed25519Gcm, F.ed25519GcmFingerprint),
    ])
    func decryptsEncryptedOpenSSHKeys(text: String, fingerprint: String) throws {
        #expect(KeyImporter.inspect(text) == .openSSH(encrypted: true))
        let imported = try KeyImporter.importKey(text, passphrase: F.passphrase)
        #expect(imported.key.publicKey.sha256Fingerprint == fingerprint)
    }

    @Test func encryptedKeyNeedsPassphrase() {
        #expect(throws: SSHKeyError.passphraseRequired) { try KeyImporter.importKey(F.ed25519Enc) }
        #expect(throws: SSHKeyError.passphraseRequired) { try KeyImporter.importKey(F.ed25519Enc, passphrase: "") }
    }

    @Test(arguments: [F.ed25519Enc, F.p384Enc, F.ed25519Aes256cbc, F.ed25519Gcm])
    func wrongPassphraseIsReported(text: String) {
        #expect(throws: SSHKeyError.wrongPassphrase) { try KeyImporter.importKey(text, passphrase: "nope") }
    }

    @Test func importsPEMAndPKCS8() throws {
        let sec1 = try KeyImporter.importKey(F.p256Pem)
        #expect(sec1.key.publicKey.sha256Fingerprint == F.p256PemFingerprint)
        let ed = try KeyImporter.importKey(F.ed25519Pkcs8)
        #expect(ed.key.publicKey.sha256Fingerprint == F.ed25519Pkcs8Fingerprint)
        #expect(ed.key.publicKey.openSSHString() == F.ed25519Pkcs8Public)
        let p384 = try KeyImporter.importKey(F.p384Pkcs8)
        #expect(p384.key.publicKey.openSSHString() == F.p384Pkcs8Public)
    }

    @Test func rsaIsRefusedWithGuidance() {
        #expect(throws: SSHKeyError.unsupportedKeyType("ssh-rsa")) { try KeyImporter.importKey(F.rsaPlain) }
        #expect(throws: SSHKeyError.unsupportedKeyType("RSA")) { try KeyImporter.importKey(F.rsaPkcs8) }
        #expect(throws: SSHKeyError.unsupportedKeyType("RSA")) {
            try KeyImporter.importKey("-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----\n")
        }
        let message = SSHKeyError.unsupportedKeyType("RSA").localizedDescription
        #expect(message.contains("Ed25519"))
    }

    @Test func otherInputsGetClearErrors() {
        #expect(KeyImporter.inspect("hello") == .unsupported(.unrecognizedFormat))
        #expect(KeyImporter.inspect(F.ed25519PlainPublic) == .unsupported(.unsupportedKeyType("this is a public key; paste the private key instead")))
        #expect(KeyImporter.inspect("PuTTY-User-Key-File-3: ssh-ed25519\n") != .pem)
        if case .unsupported(.unsupportedCipher) = KeyImporter.inspect("-----BEGIN ENCRYPTED PRIVATE KEY-----\nAA\n-----END ENCRYPTED PRIVATE KEY-----") {
        } else {
            Issue.record("encrypted PKCS#8 should be reported as an unsupported cipher")
        }
    }

    @Test func corruptBodyIsNotACrash() {
        let damaged = F.ed25519Plain.replacingOccurrences(of: "b3BlbnNzaC1rZXktdjEAAAAA", with: "b3BlbnNzaC1rZXktdjEAAAAB")
        #expect(throws: SSHKeyError.self) { try KeyImporter.importKey(damaged) }
    }
}

@Suite struct KeyGenerationTests {
    @Test(arguments: KeyAlgorithm.allCases)
    func encodeDecodeRoundTrip(algorithm: KeyAlgorithm) throws {
        let key = SSHPrivateKey.generate(algorithm)
        let plain = try OpenSSHKeyFile.encode(key, comment: "me@phone", passphrase: nil)
        let back = try KeyImporter.importKey(plain)
        #expect(back.key.publicKey == key.publicKey)
        #expect(back.comment == "me@phone")
        #expect(back.key.rawScalar == key.rawScalar)
    }

    @Test func encryptedRoundTrip() throws {
        let key = SSHPrivateKey.generate(.ed25519)
        let pem = try OpenSSHKeyFile.encode(key, comment: "backup", passphrase: "s3cret", rounds: 2)
        #expect(try OpenSSHKeyFile.isEncrypted(pem: pem))
        #expect(throws: SSHKeyError.wrongPassphrase) { try KeyImporter.importKey(pem, passphrase: "nope") }
        #expect(try KeyImporter.importKey(pem, passphrase: "s3cret").key.publicKey == key.publicKey)
    }

    @Test func publicKeyLineParsesBack() throws {
        let key = SSHPrivateKey.generate(.ecdsaP256)
        let line = key.publicKey.openSSHString(comment: "phone")
        #expect(line.hasPrefix("ecdsa-sha2-nistp256 AAAA"))
        #expect(line.hasSuffix(" phone"))
        #expect(try SSHPublicKey(openSSH: line) == key.publicKey)
        #expect(throws: SSHKeyError.invalidPublicKey) { try SSHPublicKey(openSSH: "ssh-rsa " + line.split(separator: " ")[1]) }
    }

    @Test func fingerprintMatchesSSHKeygenForFixtures() throws {
        #expect(try SSHPublicKey(openSSH: KeyFixtures.ed25519PlainPublic).sha256Fingerprint == KeyFixtures.ed25519PlainFingerprint)
        // Host keys may be RSA: parsing and fingerprinting still work.
        #expect(try SSHPublicKey(openSSH: KeyFixtures.rsaPlainPublic).sha256Fingerprint == KeyFixtures.rsaPlainFingerprint)
    }

    /// The files Portlight writes must be readable by OpenSSH itself.
    @Test(arguments: [(KeyAlgorithm.ed25519, nil as String?), (.ecdsaP521, nil), (.ed25519, "pass phrase"), (.ecdsaP256, "pass phrase")])
    func sshKeygenReadsOurFiles(algorithm: KeyAlgorithm, passphrase: String?) throws {
        let key = SSHPrivateKey.generate(algorithm)
        let pem = try OpenSSHKeyFile.encode(key, comment: "x", passphrase: passphrase, rounds: 2)
        let file = try temporaryFile(pem)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let result = runTool("/usr/bin/ssh-keygen", ["-y", "-P", passphrase ?? "", "-f", file.path]) else { return }
        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.hasPrefix(key.publicKey.openSSHString()))
    }
}
