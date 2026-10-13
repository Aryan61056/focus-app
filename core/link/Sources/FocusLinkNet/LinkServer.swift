import Foundation
import Network
import Observation

/// The Mac's end: advertises itself on the local network, pairs new phones with a code, and talks to known ones over an
/// encrypted channel. It never reaches out to the internet and holds no accounts; a phone that is not paired gets nothing.
@MainActor @Observable
public final class LinkServer {
    public struct Phone: Identifiable, Equatable, Sendable { public var id: UUID; public var name: String }

    public private(set) var port: UInt16?
    /// The code on screen while pairing is open, otherwise nil.
    public private(set) var pairingCode: PairingCode?
    public private(set) var connected: [Phone] = []
    public private(set) var lastError: String?

    @ObservationIgnored public var onMessage: ((LinkMessage, UUID) -> Void)?
    @ObservationIgnored public var onConnected: ((UUID) -> Void)?
    @ObservationIgnored public var onPaired: ((PairedDevice) -> Void)?

    @ObservationIgnored private let macName: String
    @ObservationIgnored private let macID: UUID
    @ObservationIgnored private let registry: any DeviceRegistry
    @ObservationIgnored private let advertise: Bool
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var peers: [ObjectIdentifier: Peer] = [:]
    @ObservationIgnored private var pairingTimeout: Task<Void, Never>?
    @ObservationIgnored private var failedPairings = 0
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var restart: Task<Void, Never>?
    static let maxFailedPairings = 5

    private final class Peer {
        let io: FramedConnection
        var handshake: ServerHandshake
        var channel: SecureChannel?
        var deviceID: UUID?
        var watchdog: Task<Void, Never>?
        init(io: FramedConnection, handshake: ServerHandshake) { self.io = io; self.handshake = handshake }
    }

    public init(macName: String, macID: UUID, registry: any DeviceRegistry, advertise: Bool = true) {
        self.macName = macName; self.macID = macID; self.registry = registry; self.advertise = advertise
    }

    public func start() throws {
        wanted = true
        guard listener == nil else { return }
        let l = try NWListener(using: LinkTransport.parameters())
        if advertise {
            l.service = NWListener.Service(name: macName, type: LinkTransport.serviceType, txtRecord: NWTXTRecord(["id": macID.uuidString]))
        }
        l.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready: self.port = self.listener?.port?.rawValue
                case .failed(let e):
                    // The network changed under us, or the Mac woke from sleep: try again shortly instead of staying deaf.
                    self.lastError = e.localizedDescription; self.listener?.cancel(); self.listener = nil; self.port = nil
                    self.scheduleRestart()
                default: break
                }
            }
        }
        l.newConnectionHandler = { [weak self] c in MainActor.assumeIsolated { self?.accept(c) } }
        listener = l
        l.start(queue: .main)
    }

    private func scheduleRestart() {
        guard wanted else { return }
        restart?.cancel()
        restart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.wanted, self.listener == nil else { return }
            try? self.start()
        }
    }

    /// Start over: used after the Mac wakes up, when the listener and its Bonjour entry may be stale.
    public func restartListening() {
        guard wanted else { return }
        listener?.cancel(); listener = nil; port = nil
        for p in peers.values { p.io.close() }
        peers = [:]; connected = []
        try? start()
    }

    public func stop() {
        wanted = false; restart?.cancel()
        endPairing()
        listener?.cancel(); listener = nil; port = nil
        for p in peers.values { p.io.close() }
        peers = [:]; connected = []
    }

    /// Opens pairing for a few minutes and returns the code to show. Five wrong tries close it early.
    @discardableResult
    public func beginPairing(timeout: TimeInterval = 300) -> PairingCode {
        let code = PairingCode.random()
        pairingCode = code; failedPairings = 0
        pairingTimeout?.cancel()
        pairingTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.endPairing()
        }
        return code
    }

    public func endPairing() { pairingTimeout?.cancel(); pairingTimeout = nil; pairingCode = nil }

    /// Forget a phone: it is dropped now and refused from then on.
    public func unpair(_ id: UUID) {
        registry.remove(id)
        for (k, p) in peers where p.deviceID == id { p.io.close(); peers[k] = nil }
        connected.removeAll { $0.id == id }
    }

    public func send(_ message: LinkMessage, to id: UUID? = nil) {
        guard let plain = try? LinkCoding.encode(message) else { return }
        for p in peers.values where p.channel != nil && (id == nil || p.deviceID == id) {
            if let sealed = try? p.channel?.seal(plain) { p.io.send(sealed) }
        }
    }

    // MARK: connections
    private func accept(_ c: NWConnection) {
        let io = FramedConnection(c)
        let registry = registry
        let peer = Peer(io: io, handshake: ServerHandshake(macName: macName, macID: macID, code: pairingCode, lookup: { id in registry.device(id) }))
        let key = ObjectIdentifier(io)
        peers[key] = peer
        io.onFrame = { [weak self, weak peer] frame in if let self, let peer { self.received(frame, from: peer, key: key) } }
        io.onClose = { [weak self] _ in self?.dropped(key) }
        // A connection that has not finished the handshake in ten seconds is not a phone worth waiting for.
        peer.watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.peers[key]?.channel == nil else { return }
            self.peers[key]?.io.close()
        }
        io.start()
    }

    private func dropped(_ key: ObjectIdentifier) {
        guard let p = peers.removeValue(forKey: key) else { return }
        p.watchdog?.cancel()
        if let id = p.deviceID, !peers.values.contains(where: { $0.deviceID == id && $0.channel != nil }) { connected.removeAll { $0.id == id } }
    }

    private func received(_ frame: Data, from peer: Peer, key: ObjectIdentifier) {
        if peer.channel != nil {
            guard var ch = peer.channel, let plain = try? ch.open(frame), let m = try? LinkCoding.decode(LinkMessage.self, from: plain) else { peer.io.close(); return }
            peer.channel = ch
            if let id = peer.deviceID { onMessage?(m, id) }
            return
        }
        guard let h = try? LinkCoding.decode(Handshake.self, from: frame) else { peer.io.close(); return }
        for step in peer.handshake.handle(h) {
            switch step {
            case .send(let out): if let d = try? LinkCoding.encode(out) { peer.io.send(d) }
            case .paired(let device):
                registry.add(device)
                endPairing()
                onPaired?(device)
            case .established(let id, let channel):
                peer.channel = channel; peer.deviceID = id; peer.watchdog?.cancel()
                let name = registry.device(id)?.name ?? "iPhone"
                if !connected.contains(where: { $0.id == id }) { connected.append(Phone(id: id, name: name)) }
                onConnected?(id)
            case .failed(let why):
                if why == .wrongCode {
                    failedPairings += 1
                    if failedPairings >= Self.maxFailedPairings { endPairing() }
                }
                // The rejection message was queued first; close once it has had a moment to leave.
                Task { [weak self] in try? await Task.sleep(for: .milliseconds(200)); self?.peers[key]?.io.close() }
            }
        }
    }
}
