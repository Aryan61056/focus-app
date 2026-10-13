import Foundation

/// The code the Mac shows while it is pairing a phone: 80 random bits as 16 characters, e.g. K7QM-2XD9-PWRB-4HTN.
/// Eighty bits is too many to guess even offline, so a recorded handshake gives an attacker nothing to grind on.
public struct PairingCode: Equatable, Sendable {
    public static let byteCount = 10
    /// Crockford base32: no I, L, O or U, so a code read aloud or off a screen is hard to mistype.
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public let bytes: Data

    public init(bytes: Data) { precondition(bytes.count == Self.byteCount); self.bytes = bytes }

    public static func random() -> PairingCode { PairingCode(bytes: randomBytes(byteCount)) }

    /// 16 characters in four groups of four.
    public var display: String {
        var out: [Character] = []
        var acc = 0, bits = 0
        for b in bytes {
            acc = (acc << 8) | Int(b); bits += 8
            while bits >= 5 { bits -= 5; out.append(Self.alphabet[(acc >> bits) & 31]) }
            acc &= (1 << bits) - 1
        }
        return stride(from: 0, to: out.count, by: 4).map { String(out[$0..<min($0 + 4, out.count)]) }.joined(separator: "-")
    }

    /// Reads what a person typed: any case, with or without dashes and spaces, and O/I/L read as 0/1/1.
    public init?(entered text: String) {
        var out = Data()
        var acc = 0, bits = 0, count = 0
        for ch in text.uppercased() where ch != "-" && !ch.isWhitespace {
            let c: Character = ch == "O" ? "0" : (ch == "I" || ch == "L") ? "1" : ch
            guard let v = Self.alphabet.firstIndex(of: c) else { return nil }
            acc = (acc << 5) | v; bits += 5; count += 1
            if bits >= 8 { bits -= 8; out.append(UInt8((acc >> bits) & 0xFF)); acc &= (1 << bits) - 1 }
        }
        guard count == 16, out.count == Self.byteCount else { return nil }
        self.bytes = out
    }
}

func randomBytes(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8.random(in: .min ... .max) }) }
