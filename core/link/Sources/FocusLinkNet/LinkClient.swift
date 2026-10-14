import Foundation
import Network
import Observation

/// The phone's end. It finds the paired Mac on the local network, proves it knows the shared key, and keeps the connection up,
/// reconnecting quietly when the Mac sleeps or the phone changes network.
@MainActor @Observable
public final class LinkClient {
    public enum Status: Equatable, Sendable {
        case idle
        case searching
        case connecting
        case connected
        case failed(String)
    }
    public struct FoundMac: Identifiable, Equatable, @unchecked Sendable {
        public var id: UUID
        public var name: String
        public var endpoint: NWEndpoint
    }

    public private(set) var status = Status.idle
    public private(set) var found: [FoundMac] = []

    @ObservationIgnored public var onMessage: ((LinkMessage) -> Void)?
    @ObservationIgnored public var onConnected: (() -> Void)?

    @ObservationIgnored private var io: FramedConnection?
    @ObservationIgnored private var handshake: ClientHandshake?
    @ObservationIgnored private var channel: SecureChannel?
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var following: PairedMac?
    @ObservationIgnored private var pairing: (code: PairingCode, name: String, completion: (Result<PairedMac, HandshakeFailure>) -> Void)?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var attempt = 0

    public init() {}

    // MARK: finding Macs
    public func browse() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: LinkTransport.serviceType, domain: nil), using: LinkTransport.parameters())
        b.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.found = results.compactMap { r in
                    guard case .service(let name, _, _, _) = r.endpoint,
                          case .bonjour(let txt) = r.metadata, let raw = txt["id"], let id = UUID(uuidString: raw) else { return nil }
                    return FoundMac(id: id, name: name, endpoint: r.endpoint)
                }
                self.connectIfPossible()
            }
        }
        b.start(queue: .main)
        browser = b
        if status == .idle { status = .searching }
    }

    public func stopBrowsing() { browser?.cancel(); browser = nil; found = [] }

    // MARK: pairing
    /// Pair with a Mac that is showing `code`. Calls back once, with the Mac to remember or the reason it failed.
    public func pair(with mac: FoundMac, code: PairingCode, deviceName: String, completion: @escaping (Result<PairedMac, HandshakeFailure>) -> Void) {
        pair(endpoint: mac.endpoint, code: code, deviceName: deviceName, completion: completion)
    }

    public func pair(endpoint: NWEndpoint, code: PairingCode, deviceName: String, completion: @escaping (Result<PairedMac, HandshakeFailure>) -> Void) {
        retry?.cancel(); drop()
        pairing = (code, deviceName, completion)
        status = .connecting
        open(endpoint, ClientHandshake(mode: .pair(code, deviceName: deviceName)))
    }

    // MARK: staying connected
    /// Keep a connection to this Mac: find it, connect, and come back after any drop.
    public func follow(_ mac: PairedMac) {
        following = mac; attempt = 0
        browse()
        connectIfPossible()
    }

    /// Connect to a known address (used by tests, and by anything that already has an endpoint).
    public func connect(_ mac: PairedMac, at endpoint: NWEndpoint) {
        following = mac
        status = .connecting
        open(endpoint, ClientHandshake(mode: .connect(mac)))
    }

    public func unfollow() { following = nil; retry?.cancel(); drop(); status = .idle }

    public func send(_ message: LinkMessage) {
        guard var ch = channel, let io, let plain = try? LinkCoding.encode(message), let sealed = try? ch.seal(plain) else { return }
        channel = ch
        io.send(sealed)
    }

    // MARK: internals
    private func connectIfPossible() {
        guard let mac = following, io == nil, pairing == nil, let hit = found.first(where: { $0.id == mac.macID }) else { return }
        status = .connecting
        open(hit.endpoint, ClientHandshake(mode: .connect(mac)))
    }

    private func open(_ endpoint: NWEndpoint, _ h: ClientHandshake) {
        drop()
        var h = h
        handshake = h
        let io = FramedConnection(NWConnection(to: endpoint, using: LinkTransport.parameters()))
        self.io = io
        io.onClose = { [weak self, weak io] why in
            guard let self, self.io === io else { return }
            self.closed(why)
        }
        io.onFrame = { [weak self, weak io] frame in
            guard let self, self.io === io else { return }
            self.received(frame)
        }
        let first = h.start(); handshake = h
        io.start()
        // The first message goes out as soon as the connection is up: queue it now, NWConnection holds it until ready.
        if let d = try? LinkCoding.encode(first) { io.send(d) }
    }

    private func received(_ frame: Data) {
        if channel != nil {
            guard var ch = channel, let plain = try? ch.open(frame), let m = try? LinkCoding.decode(LinkMessage.self, from: plain) else { drop(); scheduleRetry(); return }
            channel = ch
            onMessage?(m)
            return
        }
        guard var h = handshake, let msg = try? LinkCoding.decode(Handshake.self, from: frame) else { drop(); return }
        let steps = h.handle(msg)
        handshake = h
        for step in steps {
            switch step {
            case .send(let out): if let d = try? LinkCoding.encode(out) { io?.send(d) }
            case .paired(let mac):
                let done = pairing?.completion; pairing = nil
                drop(); status = .idle
                done?(.success(mac))
            case .established(let ch):
                channel = ch; attempt = 0; status = .connected
                onConnected?()
            case .failed(let why):
                if let done = pairing?.completion { pairing = nil; drop(); status = .idle; done(.failure(why)); return }
                // An unknown or unverifiable Mac will not get better by retrying quickly.
                drop(); status = .failed(why == .unknownDevice ? "This Mac no longer knows this phone." : "Could not verify the Mac.")
                if why != .unknownDevice { scheduleRetry() }
            }
        }
    }

    private func closed(_ why: String?) {
        let wasPairing = pairing
        io = nil; channel = nil; handshake = nil
        if let p = wasPairing { pairing = nil; status = .idle; p.completion(.failure(.protocolError)); return }
        if following != nil { if status == .connected || status == .connecting { status = .searching }; scheduleRetry() }
        else { status = .idle }
    }

    private func drop() {
        let old = io
        io = nil; channel = nil; handshake = nil
        old?.onClose = nil; old?.onFrame = nil; old?.close()
    }

    /// Back off 1, 2, 4, 8 then 15 seconds. The browser usually reconnects us sooner, when the Mac's service reappears.
    private func scheduleRetry() {
        guard following != nil else { return }
        retry?.cancel()
        attempt += 1
        let delay = min(15.0, pow(2.0, Double(attempt - 1)))
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.connectIfPossible()
        }
    }
}
