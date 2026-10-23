import Crypto
import _CryptoExtras
import Foundation

/// Reads and writes the `openssh-key-v1` private key format (OpenSSH's
/// PROTOCOL.key), the format `ssh-keygen` has written by default since 7.8.
public enum OpenSSHKeyFile {
    static let magic = Array("openssh-key-v1\0".utf8)
    static let pemLabel = "OPENSSH PRIVATE KEY"

    /// The default number of bcrypt rounds when Portlight encrypts a key, the
    /// same as `ssh-keygen -a 16`.
    public static let defaultRounds = 16

    // MARK: Decoding

    public static func decode(pem: String, passphrase: String?) throws -> (key: SSHPrivateKey, comment: String) {
        guard let body = PEM.body(of: pem, label: pemLabel) else { throw SSHKeyError.unrecognizedFormat }
        return try decode(binary: body, passphrase: passphrase)
    }

    /// Whether the file needs a passphrase, without decrypting it.
    public static func isEncrypted(pem: String) throws -> Bool {
        guard let body = PEM.body(of: pem, label: pemLabel) else { throw SSHKeyError.unrecognizedFormat }
        let header = try readHeader(body)
        return header.cipher != "none"
    }

    struct Header {
        var cipher: String
        var kdf: String
        var kdfOptions: [UInt8]
        var publicBlob: [UInt8]
        var encrypted: [UInt8]
        var trailing: [UInt8]
    }

    static func readHeader(_ data: [UInt8]) throws -> Header {
        guard data.count > magic.count, Array(data.prefix(magic.count)) == magic else {
            throw SSHKeyError.unrecognizedFormat
        }
        do {
            var reader = SSHReader(data.dropFirst(magic.count))
            let cipher = try reader.readUTF8String()
            let kdf = try reader.readUTF8String()
            let kdfOptions = try reader.readString()
            let count = try reader.readUInt32()
            guard count == 1 else { throw SSHKeyError.corrupt("expected exactly one key, found \(count)") }
            let publicBlob = try reader.readString()
            let encrypted = try reader.readString()
            return Header(cipher: cipher, kdf: kdf, kdfOptions: kdfOptions, publicBlob: publicBlob,
                          encrypted: encrypted, trailing: reader.readRemaining())
        } catch let error as SSHWireError {
            throw SSHKeyError.corrupt("key file header: \(error)")
        }
    }

    public static func decode(binary data: [UInt8], passphrase: String?) throws -> (key: SSHPrivateKey, comment: String) {
        let header = try readHeader(data)
        let publicKey = try SSHPublicKey(blob: header.publicBlob)
        guard let algorithm = publicKey.keyAlgorithm else {
            throw SSHKeyError.unsupportedKeyType(publicKey.algorithmName)
        }

        let plain: [UInt8]
        if header.cipher == "none" {
            guard header.kdf == "none" else { throw SSHKeyError.corrupt("cipher none with kdf \(header.kdf)") }
            plain = header.encrypted
        } else {
            guard let passphrase, !passphrase.isEmpty else { throw SSHKeyError.passphraseRequired }
            guard header.kdf == "bcrypt" else { throw SSHKeyError.unsupportedKDF(header.kdf) }
            let cipher = try KeyFileCipher(name: header.cipher)
            var options = SSHReader(header.kdfOptions)
            let salt: [UInt8]
            let rounds: UInt32
            do {
                salt = try options.readString()
                rounds = try options.readUInt32()
            } catch {
                throw SSHKeyError.corrupt("bcrypt options")
            }
            guard rounds >= 1, rounds <= 10_000 else { throw SSHKeyError.corrupt("bcrypt rounds \(rounds)") }
            let derived = try BcryptPBKDF.derive(
                password: Array(passphrase.utf8), salt: salt,
                keyLength: cipher.keyLength + cipher.ivLength, rounds: Int(rounds))
            let key = Array(derived.prefix(cipher.keyLength))
            let iv = Array(derived.dropFirst(cipher.keyLength))
            plain = try cipher.decrypt(header.encrypted, tag: Array(header.trailing.prefix(cipher.tagLength)),
                                       key: key, iv: iv)
        }

        var reader = SSHReader(plain)
        do {
            let check1 = try reader.readUInt32()
            let check2 = try reader.readUInt32()
            guard check1 == check2 else {
                throw header.cipher == "none" ? SSHKeyError.corrupt("check bytes differ") : SSHKeyError.wrongPassphrase
            }
            let type = try reader.readUTF8String()
            guard type == algorithm.sshName else { throw SSHKeyError.corrupt("private key type \(type) does not match public key") }

            let privateKey: SSHPrivateKey
            switch algorithm {
            case .ed25519:
                let pub = try reader.readString()
                let secret = try reader.readString()
                guard pub.count == 32, secret.count == 64, Array(secret.suffix(32)) == pub else {
                    throw SSHKeyError.corrupt("ed25519 key lengths")
                }
                privateKey = try SSHPrivateKey(algorithm: .ed25519, rawScalar: Array(secret.prefix(32)))
            case .ecdsaP256, .ecdsaP384, .ecdsaP521:
                let curve = try reader.readUTF8String()
                guard curve == algorithm.curveName else { throw SSHKeyError.corrupt("curve \(curve)") }
                _ = try reader.readString()  // Q, recomputed from d below and compared via the public key
                let scalar = try reader.readMPIntMagnitude()
                privateKey = try SSHPrivateKey(algorithm: algorithm, rawScalar: scalar)
            }
            let comment = (try? reader.readUTF8String()) ?? ""
            // The padding must be 1, 2, 3, ... (PROTOCOL.key).
            let padding = reader.readRemaining()
            for (index, byte) in padding.enumerated() where byte != UInt8(truncatingIfNeeded: index + 1) {
                throw SSHKeyError.corrupt("bad padding")
            }
            guard privateKey.publicKey.blob == header.publicBlob else {
                throw SSHKeyError.corrupt("private key does not match its public key")
            }
            return (privateKey, comment)
        } catch let error as SSHWireError {
            throw header.cipher == "none" ? SSHKeyError.corrupt("private section: \(error)") : SSHKeyError.wrongPassphrase
        } catch let error as CryptoKitError {
            throw SSHKeyError.corrupt("key material: \(error)")
        }
    }

    // MARK: Encoding

    /// Encodes a key as `-----BEGIN OPENSSH PRIVATE KEY-----`, encrypted with
    /// aes256-ctr and bcrypt when a passphrase is given (as `ssh-keygen` does).
    public static func encode(_ key: SSHPrivateKey, comment: String, passphrase: String?,
                              rounds: Int = defaultRounds) throws -> String {
        let encrypted = passphrase.map { !$0.isEmpty } ?? false
        let cipher = try KeyFileCipher(name: encrypted ? "aes256-ctr" : "none")

        var priv = SSHWriter()
        let check = UInt32.random(in: .min ... .max)
        priv.writeUInt32(check)
        priv.writeUInt32(check)
        priv.writeString(key.algorithm.sshName)
        switch key {
        case .ed25519:
            let pub = key.publicPoint
            priv.writeString(pub)
            priv.writeString(key.rawScalar + pub)
        case .ecdsaP256, .ecdsaP384, .ecdsaP521:
            priv.writeString(key.algorithm.curveName!)
            priv.writeString(key.publicPoint)
            priv.writeMPInt(unsigned: key.rawScalar)
        }
        priv.writeString(comment)
        var section = priv.bytes
        var pad: UInt8 = 1
        while section.count % cipher.blockSize != 0 {
            section.append(pad)
            pad += 1
        }

        var kdfOptions = SSHWriter()
        var body = section
        if encrypted, let passphrase {
            var salt = [UInt8](repeating: 0, count: 16)
            var rng = SystemRandomNumberGenerator()
            for i in salt.indices { salt[i] = rng.next() }
            kdfOptions.writeString(salt)
            kdfOptions.writeUInt32(UInt32(rounds))
            let derived = try BcryptPBKDF.derive(password: Array(passphrase.utf8), salt: salt,
                                                 keyLength: cipher.keyLength + cipher.ivLength, rounds: rounds)
            body = try cipher.encrypt(section, key: Array(derived.prefix(cipher.keyLength)),
                                      iv: Array(derived.dropFirst(cipher.keyLength)))
        }

        var file = SSHWriter()
        file.writeRaw(magic)
        file.writeString(cipher.name)
        file.writeString(encrypted ? "bcrypt" : "none")
        file.writeString(kdfOptions.bytes)
        file.writeUInt32(1)
        file.writeString(key.publicKey.blob)
        file.writeString(body)
        return PEM.encode(file.bytes, label: pemLabel)
    }
}

/// The ciphers `openssh-key-v1` files are encrypted with.
struct KeyFileCipher {
    enum Mode { case none, ctr, cbc, gcm }
    let name: String
    let mode: Mode
    let keyLength: Int
    var ivLength: Int { mode == .gcm ? 12 : (mode == .none ? 0 : 16) }
    var blockSize: Int { mode == .none ? 8 : 16 }
    var tagLength: Int { mode == .gcm ? 16 : 0 }

    init(name: String) throws {
        self.name = name
        switch name {
        case "none": (mode, keyLength) = (.none, 0)
        case "aes128-ctr": (mode, keyLength) = (.ctr, 16)
        case "aes192-ctr": (mode, keyLength) = (.ctr, 24)
        case "aes256-ctr": (mode, keyLength) = (.ctr, 32)
        case "aes128-cbc": (mode, keyLength) = (.cbc, 16)
        case "aes192-cbc": (mode, keyLength) = (.cbc, 24)
        case "aes256-cbc": (mode, keyLength) = (.cbc, 32)
        case "aes128-gcm@openssh.com": (mode, keyLength) = (.gcm, 16)
        case "aes256-gcm@openssh.com": (mode, keyLength) = (.gcm, 32)
        default: throw SSHKeyError.unsupportedCipher(name)
        }
    }

    func decrypt(_ data: [UInt8], tag: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        guard data.count % blockSize == 0 else { throw SSHKeyError.corrupt("encrypted length") }
        let symmetric = SymmetricKey(data: key)
        do {
            switch mode {
            case .none:
                return data
            case .ctr:
                return Array(try AES._CTR.decrypt(data, using: symmetric, nonce: .init(nonceBytes: iv)))
            case .cbc:
                return Array(try AES._CBC.decrypt(data, using: symmetric, iv: .init(ivBytes: iv), noPadding: true))
            case .gcm:
                guard tag.count == 16 else { throw SSHKeyError.corrupt("missing GCM tag") }
                let box = try AES.GCM.SealedBox(nonce: .init(data: iv), ciphertext: data, tag: tag)
                do {
                    return Array(try AES.GCM.open(box, using: symmetric))
                } catch {
                    throw SSHKeyError.wrongPassphrase
                }
            }
        } catch let error as SSHKeyError {
            throw error
        } catch {
            throw SSHKeyError.corrupt("decrypting: \(error)")
        }
    }

    func encrypt(_ data: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        let symmetric = SymmetricKey(data: key)
        switch mode {
        case .none: return data
        case .ctr: return Array(try AES._CTR.encrypt(data, using: symmetric, nonce: .init(nonceBytes: iv)))
        case .cbc: return Array(try AES._CBC.encrypt(data, using: symmetric, iv: .init(ivBytes: iv), noPadding: true))
        case .gcm: throw SSHKeyError.unsupportedCipher(name)  // never chosen for writing
        }
    }
}

/// Minimal PEM armour handling.
enum PEM {
    /// The base64 body between `-----BEGIN label-----` and `-----END label-----`.
    static func body(of text: String, label: String) -> [UInt8]? {
        let begin = "-----BEGIN \(label)-----"
        let end = "-----END \(label)-----"
        guard let start = text.range(of: begin), let stop = text.range(of: end, range: start.upperBound..<text.endIndex) else {
            return nil
        }
        let inner = text[start.upperBound..<stop.lowerBound]
        // Skip RFC 1421 headers such as "Proc-Type:" if present.
        let lines = inner.split(whereSeparator: \.isNewline).filter { !$0.contains(":") }
        return Base64.decode(lines.joined())
    }

    /// The first `-----BEGIN X-----` label in `text`.
    static func firstLabel(in text: String) -> String? {
        guard let start = text.range(of: "-----BEGIN ") else { return nil }
        guard let stop = text.range(of: "-----", range: start.upperBound..<text.endIndex) else { return nil }
        return String(text[start.upperBound..<stop.lowerBound])
    }

    static func encode(_ bytes: [UInt8], label: String) -> String {
        let encoded = Base64.encode(bytes)
        var lines: [String] = []
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let next = encoded.index(index, offsetBy: 70, limitedBy: encoded.endIndex) ?? encoded.endIndex
            lines.append(String(encoded[index..<next]))
            index = next
        }
        return "-----BEGIN \(label)-----\n" + lines.joined(separator: "\n") + "\n-----END \(label)-----\n"
    }
}
