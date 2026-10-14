import Foundation
import CryptoKit

/// One direction pair of an authenticated, encrypted connection. Each frame is sealed with ChaCha20-Poly1305 under a per-direction
/// key, and the nonce is a counter both sides keep, so a replayed, dropped, reordered or altered frame fails to open.
public struct SecureChannel: Sendable {
    public enum Failure: Error, Equatable { case cannotOpen }

    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var sent: UInt64 = 0
    private var received: UInt64 = 0

    init(sendKey: SymmetricKey, receiveKey: SymmetricKey) { self.sendKey = sendKey; self.receiveKey = receiveKey }

    private static func nonce(_ counter: UInt64) throws -> ChaChaPoly.Nonce {
        var d = Data(count: 4)
        withUnsafeBytes(of: counter.bigEndian) { d.append(contentsOf: $0) }
        return try ChaChaPoly.Nonce(data: d)
    }

    public mutating func seal(_ plain: Data) throws -> Data {
        let box = try ChaChaPoly.seal(plain, using: sendKey, nonce: Self.nonce(sent))
        sent += 1
        return Data(box.ciphertext + box.tag)   // a fresh Data, not a slice of the box
    }

    public mutating func open(_ frame: Data) throws -> Data {
        guard frame.count >= 16 else { throw Failure.cannotOpen }
        do {
            let box = try ChaChaPoly.SealedBox(nonce: Self.nonce(received), ciphertext: frame.dropLast(16), tag: frame.suffix(16))
            let plain = try ChaChaPoly.open(box, using: receiveKey)
            received += 1
            return plain
        } catch { throw Failure.cannotOpen }
    }

    /// Both directions from one long-term device key and the two fresh nonces of this connection.
    static func derive(deviceKey: SymmetricKey, clientNonce: Data, serverNonce: Data, asClient: Bool) -> SecureChannel {
        func key(_ label: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: deviceKey, salt: clientNonce + serverNonce, info: Data(label.utf8), outputByteCount: 32)
        }
        let toServer = key("focuslink/client-to-server/v1"), toClient = key("focuslink/server-to-client/v1")
        return asClient ? SecureChannel(sendKey: toServer, receiveKey: toClient) : SecureChannel(sendKey: toClient, receiveKey: toServer)
    }
}
