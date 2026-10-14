import Foundation
import CryptoKit

/// A phone the Mac has agreed to talk to. `key` is 32 random bytes only these two devices know.
public struct PairedDevice: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var key: Data
    public var pairedAt: Date
    public init(id: UUID, name: String, key: Data, pairedAt: Date) { self.id = id; self.name = name; self.key = key; self.pairedAt = pairedAt }
}

/// What the phone keeps about a Mac it has paired with.
public struct PairedMac: Codable, Equatable, Sendable {
    public var macID: UUID
    public var macName: String
    /// This phone's id as the Mac knows it.
    public var deviceID: UUID
    public var key: Data
    public init(macID: UUID, macName: String, deviceID: UUID, key: Data) { self.macID = macID; self.macName = macName; self.deviceID = deviceID; self.key = key }
}

/// Messages before the channel is encrypted. Nothing secret is in them: a code is proven, never sent, and the long-term key
/// only ever travels sealed under a key made from that code.
public enum Handshake: Codable, Equatable, Sendable {
    case pairHello(deviceName: String, nonce: Data)
    case pairChallenge(nonce: Data, macName: String, macID: UUID)
    case pairProof(Data)
    case pairGrant(sealed: Data, proof: Data)
    case hello(deviceID: UUID, nonce: Data)
    case challenge(nonce: Data, proof: Data)
    case auth(proof: Data)
    case ready
    case rejected(reason: String)
}

public enum HandshakeFailure: Error, Equatable, Sendable {
    case wrongCode, notPairing, unknownDevice, badProof, protocolError
}

enum Proof {
    static func tag(_ key: SymmetricKey, _ label: String, _ parts: Data...) -> Data {
        var h = HMAC<SHA256>(key: key)
        h.update(data: Data(label.utf8))
        for p in parts { h.update(data: p) }
        return Data(h.finalize())
    }
    static func isValid(_ tag: Data, _ key: SymmetricKey, _ label: String, _ parts: Data...) -> Bool {
        var h = HMAC<SHA256>(key: key)
        h.update(data: Data(label.utf8))
        for p in parts { h.update(data: p) }
        return h.finalize().withUnsafeBytes { ours in
            tag.count == ours.count && tag.withUnsafeBytes { theirs in zip(ours, theirs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0 }
        }
    }
    static func pairKey(_ code: PairingCode, _ cn: Data, _ sn: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: code.bytes), salt: cn + sn, info: Data("focuslink/pair/v1".utf8), outputByteCount: 32)
    }
}

extension UUID {
    var bytes: Data { withUnsafeBytes(of: uuid) { Data($0) } }
    init?(bytes: Data) {
        guard bytes.count == 16 else { return nil }
        self = UUID(uuid: bytes.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) })
    }
}

extension SymmetricKey { var data: Data { withUnsafeBytes { Data($0) } } }

// MARK: Mac side

/// The Mac's half of one connection. Feed it each plain message; it says what to send and when the connection is trusted.
public struct ServerHandshake {
    public enum Step: Sendable {
        case send(Handshake)
        case paired(PairedDevice)
        case established(deviceID: UUID, SecureChannel)
        case failed(HandshakeFailure)
    }
    private enum Stage: Sendable {
        case idle
        case pairChallenged(clientNonce: Data, serverNonce: Data, deviceName: String)
        case connectChallenged(device: PairedDevice, clientNonce: Data, serverNonce: Data)
        case done
    }

    private let macName: String, macID: UUID
    private let code: PairingCode?
    private let lookup: (UUID) -> PairedDevice?
    private var stage = Stage.idle

    /// `code` is non-nil only while the Mac is showing a pairing code; otherwise only known phones get in.
    public init(macName: String, macID: UUID, code: PairingCode?, lookup: @escaping (UUID) -> PairedDevice?) {
        self.macName = macName; self.macID = macID; self.code = code; self.lookup = lookup
    }

    private mutating func fail(_ f: HandshakeFailure, _ why: String) -> [Step] { stage = .done; return [.send(.rejected(reason: why)), .failed(f)] }

    public mutating func handle(_ m: Handshake) -> [Step] {
        switch (stage, m) {
        case (.idle, .pairHello(let name, let cn)):
            guard code != nil else { return fail(.notPairing, "This Mac is not pairing right now.") }
            guard cn.count == 16 else { return fail(.protocolError, "Bad request.") }
            let sn = randomBytes(16)
            stage = .pairChallenged(clientNonce: cn, serverNonce: sn, deviceName: String(name.prefix(60)))
            return [.send(.pairChallenge(nonce: sn, macName: macName, macID: macID))]

        case (.pairChallenged(let cn, let sn, let name), .pairProof(let p)):
            guard let code else { return fail(.notPairing, "This Mac is not pairing right now.") }
            let pk = Proof.pairKey(code, cn, sn)
            guard Proof.isValid(p, pk, "client-pair", cn, sn) else { return fail(.wrongCode, "That code is not right.") }
            let deviceKey = SymmetricKey(size: .bits256), deviceID = UUID()
            guard let sealed = try? ChaChaPoly.seal(deviceKey.data + deviceID.bytes, using: pk).combined else { return fail(.protocolError, "Could not pair.") }
            stage = .done
            let device = PairedDevice(id: deviceID, name: name, key: deviceKey.data, pairedAt: Date())
            return [.send(.pairGrant(sealed: sealed, proof: Proof.tag(pk, "server-pair", cn, sn, sealed))), .paired(device)]

        case (.idle, .hello(let did, let cn)):
            guard cn.count == 16 else { return fail(.protocolError, "Bad request.") }
            guard let device = lookup(did) else { return fail(.unknownDevice, "This phone is not paired with this Mac.") }
            let sn = randomBytes(16), key = SymmetricKey(data: device.key)
            stage = .connectChallenged(device: device, clientNonce: cn, serverNonce: sn)
            return [.send(.challenge(nonce: sn, proof: Proof.tag(key, "server", cn, sn, did.bytes)))]

        case (.connectChallenged(let device, let cn, let sn), .auth(let p)):
            let key = SymmetricKey(data: device.key)
            guard Proof.isValid(p, key, "client", cn, sn, device.id.bytes) else { return fail(.badProof, "Could not verify this phone.") }
            stage = .done
            return [.send(.ready), .established(deviceID: device.id, .derive(deviceKey: key, clientNonce: cn, serverNonce: sn, asClient: false))]

        default:
            return fail(.protocolError, "Unexpected message.")
        }
    }
}

// MARK: Phone side

public struct ClientHandshake: Sendable {
    public enum Mode: Sendable {
        case pair(PairingCode, deviceName: String)
        case connect(PairedMac)
    }
    public enum Step: Sendable {
        case send(Handshake)
        case paired(PairedMac)
        case established(SecureChannel)
        case failed(HandshakeFailure)
    }
    private enum Stage: Sendable { case fresh, awaitingChallenge, awaitingGrant(sn: Data, macName: String, macID: UUID), awaitingReady(SecureChannel), done }

    private let mode: Mode
    private let nonce = randomBytes(16)
    private var stage = Stage.fresh

    public init(mode: Mode) { self.mode = mode }

    /// The first message to send.
    public mutating func start() -> Handshake {
        stage = .awaitingChallenge
        switch mode {
        case .pair(_, let name): return .pairHello(deviceName: name, nonce: nonce)
        case .connect(let mac): return .hello(deviceID: mac.deviceID, nonce: nonce)
        }
    }

    private mutating func fail(_ f: HandshakeFailure) -> [Step] { stage = .done; return [.failed(f)] }

    public mutating func handle(_ m: Handshake) -> [Step] {
        if case .rejected(let why) = m {
            stage = .done
            if case .pair = mode { return [.failed(why.contains("code") ? .wrongCode : .notPairing)] }
            return [.failed(.unknownDevice)]
        }
        switch (stage, mode, m) {
        case (.awaitingChallenge, .pair(let code, _), .pairChallenge(let sn, let macName, let macID)):
            guard sn.count == 16 else { return fail(.protocolError) }
            let pk = Proof.pairKey(code, nonce, sn)
            stage = .awaitingGrant(sn: sn, macName: macName, macID: macID)
            return [.send(.pairProof(Proof.tag(pk, "client-pair", nonce, sn)))]

        case (.awaitingGrant(let sn, let macName, let macID), .pair(let code, _), .pairGrant(let sealed, let proof)):
            let pk = Proof.pairKey(code, nonce, sn)
            guard Proof.isValid(proof, pk, "server-pair", nonce, sn, sealed) else { return fail(.badProof) }
            guard let box = try? ChaChaPoly.SealedBox(combined: sealed), let plain = try? ChaChaPoly.open(box, using: pk), plain.count == 48,
                  let id = UUID(bytes: Data(plain.suffix(16))) else { return fail(.badProof) }
            stage = .done
            return [.paired(PairedMac(macID: macID, macName: macName, deviceID: id, key: Data(plain.prefix(32))))]

        case (.awaitingChallenge, .connect(let mac), .challenge(let sn, let proof)):
            guard sn.count == 16 else { return fail(.protocolError) }
            let key = SymmetricKey(data: mac.key)
            guard Proof.isValid(proof, key, "server", nonce, sn, mac.deviceID.bytes) else { return fail(.badProof) }
            stage = .awaitingReady(.derive(deviceKey: key, clientNonce: nonce, serverNonce: sn, asClient: true))
            return [.send(.auth(proof: Proof.tag(key, "client", nonce, sn, mac.deviceID.bytes)))]

        case (.awaitingReady(let channel), _, .ready):
            stage = .done
            return [.established(channel)]

        default:
            return fail(.protocolError)
        }
    }
}
