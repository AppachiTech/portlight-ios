import Crypto

/// Blowfish as used by bcrypt and `bcrypt_pbkdf` (OpenBSD `blf.c`): only the
/// key schedule and ECB encipherment that key derivation needs.
struct Blowfish {
    private var p: [UInt32]
    private var s0: [UInt32]
    private var s1: [UInt32]
    private var s2: [UInt32]
    private var s3: [UInt32]

    init() {
        p = BlowfishConstants.p
        s0 = BlowfishConstants.s0
        s1 = BlowfishConstants.s1
        s2 = BlowfishConstants.s2
        s3 = BlowfishConstants.s3
    }

    @inline(__always)
    private func f(_ x: UInt32) -> UInt32 {
        let a = s0[Int(x >> 24)]
        let b = s1[Int((x >> 16) & 0xFF)]
        let c = s2[Int((x >> 8) & 0xFF)]
        let d = s3[Int(x & 0xFF)]
        return ((a &+ b) ^ c) &+ d
    }

    @inline(__always)
    func encipher(_ xl: inout UInt32, _ xr: inout UInt32) {
        var l = xl ^ p[0]
        var r = xr
        var i = 1
        while i <= 16 {
            r ^= f(l) ^ p[i]
            l ^= f(r) ^ p[i + 1]
            i += 2
        }
        xl = r ^ p[17]
        xr = l
    }

    /// Reads the next big-endian word from `data`, wrapping around at the end.
    @inline(__always)
    private static func streamWord(_ data: [UInt8], _ j: inout Int) -> UInt32 {
        var word: UInt32 = 0
        for _ in 0..<4 {
            if j >= data.count { j = 0 }
            word = (word << 8) | UInt32(data[j])
            j += 1
        }
        return word
    }

    @inline(__always)
    private mutating func setS(_ box: Int, _ index: Int, _ value: UInt32) {
        switch box {
        case 0: s0[index] = value
        case 1: s1[index] = value
        case 2: s2[index] = value
        default: s3[index] = value
        }
    }

    /// `Blowfish_expandstate`: the salted key schedule.
    mutating func expandState(data: [UInt8], key: [UInt8]) {
        var j = 0
        for i in 0..<18 { p[i] ^= Self.streamWord(key, &j) }
        j = 0
        var l: UInt32 = 0
        var r: UInt32 = 0
        var i = 0
        while i < 18 {
            l ^= Self.streamWord(data, &j)
            r ^= Self.streamWord(data, &j)
            encipher(&l, &r)
            p[i] = l
            p[i + 1] = r
            i += 2
        }
        for box in 0..<4 {
            var k = 0
            while k < 256 {
                l ^= Self.streamWord(data, &j)
                r ^= Self.streamWord(data, &j)
                encipher(&l, &r)
                setS(box, k, l)
                setS(box, k + 1, r)
                k += 2
            }
        }
    }

    /// `Blowfish_expand0state`: the unsalted key schedule.
    mutating func expand0State(key: [UInt8]) {
        var j = 0
        for i in 0..<18 { p[i] ^= Self.streamWord(key, &j) }
        var l: UInt32 = 0
        var r: UInt32 = 0
        var i = 0
        while i < 18 {
            encipher(&l, &r)
            p[i] = l
            p[i + 1] = r
            i += 2
        }
        for box in 0..<4 {
            var k = 0
            while k < 256 {
                encipher(&l, &r)
                setS(box, k, l)
                setS(box, k + 1, r)
                k += 2
            }
        }
    }
}

/// `bcrypt_pbkdf` from OpenBSD, the key-derivation function OpenSSH uses to
/// encrypt `openssh-key-v1` private keys with a passphrase.
public enum BcryptPBKDF {
    public enum Error: Swift.Error, Equatable { case invalidParameters }

    private static let magic = Array("OxychromaticBlowfishSwatDynamite".utf8)
    private static let hashLength = 32

    static func bcryptHash(sha2pass: [UInt8], sha2salt: [UInt8]) -> [UInt8] {
        var state = Blowfish()
        state.expandState(data: sha2salt, key: sha2pass)
        for _ in 0..<64 {
            state.expand0State(key: sha2salt)
            state.expand0State(key: sha2pass)
        }
        var words = [UInt32](repeating: 0, count: 8)
        for i in 0..<8 {
            words[i] = UInt32(magic[4 * i]) << 24 | UInt32(magic[4 * i + 1]) << 16
                | UInt32(magic[4 * i + 2]) << 8 | UInt32(magic[4 * i + 3])
        }
        for _ in 0..<64 {
            var i = 0
            while i < 8 {
                var l = words[i]
                var r = words[i + 1]
                state.encipher(&l, &r)
                words[i] = l
                words[i + 1] = r
                i += 2
            }
        }
        var out = [UInt8](repeating: 0, count: hashLength)
        for i in 0..<8 {  // little-endian output, as in the reference
            out[4 * i + 3] = UInt8(truncatingIfNeeded: words[i] >> 24)
            out[4 * i + 2] = UInt8(truncatingIfNeeded: words[i] >> 16)
            out[4 * i + 1] = UInt8(truncatingIfNeeded: words[i] >> 8)
            out[4 * i] = UInt8(truncatingIfNeeded: words[i])
        }
        return out
    }

    /// Derives `keyLength` bytes from `password` and `salt` with `rounds` rounds.
    public static func derive(password: [UInt8], salt: [UInt8], keyLength: Int, rounds: Int) throws -> [UInt8] {
        guard rounds >= 1, !salt.isEmpty, keyLength > 0, keyLength <= hashLength * hashLength,
              salt.count <= 1 << 20 else { throw Error.invalidParameters }
        let stride = (keyLength + hashLength - 1) / hashLength
        var amount = (keyLength + stride - 1) / stride
        let sha2pass = Array(SHA512.hash(data: password))
        var key = [UInt8](repeating: 0, count: keyLength)
        var remaining = keyLength
        var count: UInt32 = 1
        while remaining > 0 {
            var countSalt = salt
            countSalt += [UInt8(count >> 24 & 0xFF), UInt8(count >> 16 & 0xFF), UInt8(count >> 8 & 0xFF), UInt8(count & 0xFF)]
            var sha2salt = Array(SHA512.hash(data: countSalt))
            var tmp = bcryptHash(sha2pass: sha2pass, sha2salt: sha2salt)
            var out = tmp
            if rounds > 1 {
                for _ in 1..<rounds {
                    sha2salt = Array(SHA512.hash(data: tmp))
                    tmp = bcryptHash(sha2pass: sha2pass, sha2salt: sha2salt)
                    for j in 0..<out.count { out[j] ^= tmp[j] }
                }
            }
            amount = min(amount, remaining)
            var written = 0
            while written < amount {
                let dest = written * stride + Int(count - 1)
                if dest >= keyLength { break }
                key[dest] = out[written]
                written += 1
            }
            remaining -= written
            count += 1
        }
        return key
    }
}
