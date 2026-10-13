import Foundation
import Network

enum LinkTransport {
    static let serviceType = "_focuslink._tcp"
    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true; tcp.enableKeepalive = true; tcp.keepaliveIdle = 10; tcp.keepaliveInterval = 5; tcp.keepaliveCount = 3
        let p = NWParameters(tls: nil, tcp: tcp)
        p.includePeerToPeer = true
        return p
    }
}

/// One NWConnection that speaks in whole frames. Everything runs on the main queue, so callbacks are plain main-actor calls.
@MainActor final class FramedConnection {
    let connection: NWConnection
    var onFrame: ((Data) -> Void)?
    var onClose: ((String?) -> Void)?
    private var reader = FrameReader()
    private var closed = false

    init(_ connection: NWConnection) { self.connection = connection }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready: self.receive()
                case .failed(let e): self.finish(e.localizedDescription)
                case .cancelled: self.finish(nil)
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }

    /// Hand the connection over once it is already running (the listener starts it before we see it).
    func send(_ payload: Data) {
        connection.send(content: FrameCodec.frame(payload), completion: .contentProcessed { [weak self] error in
            if let error { MainActor.assumeIsolated { self?.finish(error.localizedDescription) } }
        })
    }

    func close() { finish(nil) }

    private func finish(_ why: String?) {
        guard !closed else { return }
        closed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose?(why)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                if let data, !data.isEmpty {
                    self.reader.append(data)
                    do { while let f = try self.reader.next() { self.onFrame?(f) } } catch { self.finish("frame too large"); return }
                }
                if let error { self.finish(error.localizedDescription) }
                else if isComplete { self.finish(nil) }
                else { self.receive() }
            }
        }
    }
}
