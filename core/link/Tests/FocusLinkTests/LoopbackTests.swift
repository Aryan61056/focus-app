import Testing
import Foundation
import Network
@testable import FocusLinkNet

/// Real sockets on 127.0.0.1, no Bonjour (advertising is off), the same code paths the apps use.
@MainActor private func until(_ seconds: Double = 5, _ cond: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { if cond() { return true }; try? await Task.sleep(for: .milliseconds(20)) }
    return cond()
}

@MainActor private func makeServer() async throws -> (LinkServer, MemoryDeviceRegistry, NWEndpoint) {
    let registry = MemoryDeviceRegistry()
    let server = LinkServer(macName: "Test Mac", macID: UUID(), registry: registry, advertise: false)
    try server.start()
    #expect(await until { server.port != nil })
    return (server, registry, .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: server.port!)!))
}

@MainActor private func pairPhone(_ server: LinkServer, _ endpoint: NWEndpoint, using code: PairingCode? = nil) async -> Result<PairedMac, HandshakeFailure>? {
    let client = LinkClient()
    var result: Result<PairedMac, HandshakeFailure>?
    client.pair(endpoint: endpoint, code: code ?? server.pairingCode!, deviceName: "Test iPhone") { result = $0 }
    _ = await until { result != nil }
    return result
}

@MainActor @Suite(.serialized) struct LoopbackTests {
    @Test func pairThenConnectThenTalk() async throws {
        let (server, registry, endpoint) = try await makeServer()
        defer { server.stop() }
        server.beginPairing()
        let mac = try #require(try await pairPhone(server, endpoint)?.get())
        #expect(registry.devices.count == 1)
        #expect(registry.devices[0].key == mac.key)
        #expect(server.pairingCode == nil)   // the code is spent once it has been used

        var heard: [LinkMessage] = [], fromPhone: [LinkMessage] = [], connectedID: UUID?
        server.onConnected = { connectedID = $0 }
        server.onMessage = { m, _ in fromPhone.append(m) }
        let client = LinkClient()
        client.onMessage = { heard.append($0) }
        client.connect(mac, at: endpoint)
        #expect(await until { client.status == .connected && connectedID != nil })
        #expect(connectedID == mac.deviceID)
        #expect(server.connected.map(\.id) == [mac.deviceID])

        let state = SessionState(phase: .onTask, task: "Calc homework", timed: true, clockSeconds: 1500, clockRunning: true, totalSeconds: 3000)
        server.send(.state(state))
        #expect(await until { heard == [.state(state)] })
        client.send(.command(id: 7, .pause))
        #expect(await until { fromPhone == [.command(id: 7, .pause)] })
        server.send(.result(id: 7, .done), to: mac.deviceID)
        #expect(await until { heard.last == .result(id: 7, .done) })
        client.unfollow()
    }

    @Test func wrongCodeIsRefused() async throws {
        let (server, registry, endpoint) = try await makeServer()
        defer { server.stop() }
        server.beginPairing()
        let result = await pairPhone(server, endpoint, using: PairingCode.random())
        #expect({ if case .failure(.wrongCode) = result { true } else { false } }())
        #expect(registry.devices.isEmpty)
        #expect(server.pairingCode != nil)   // one wrong try does not close pairing
    }

    @Test func fiveWrongCodesClosePairing() async throws {
        let (server, _, endpoint) = try await makeServer()
        defer { server.stop() }
        server.beginPairing()
        for _ in 0..<5 { _ = await pairPhone(server, endpoint, using: PairingCode.random()) }
        #expect(await until { server.pairingCode == nil })
    }

    @Test func pairingClosedMeansNoNewPhones() async throws {
        let (server, registry, endpoint) = try await makeServer()
        defer { server.stop() }
        let code = PairingCode.random()
        let result = await pairPhone(server, endpoint, using: code)   // never called beginPairing
        #expect({ if case .failure = result { true } else { false } }())
        #expect(registry.devices.isEmpty)
    }

    @Test func aForgottenPhoneCannotConnectAndIsDroppedOnUnpair() async throws {
        let (server, registry, endpoint) = try await makeServer()
        defer { server.stop() }
        server.beginPairing()
        let mac = try #require(try await pairPhone(server, endpoint)?.get())
        let client = LinkClient()
        client.connect(mac, at: endpoint)
        #expect(await until { client.status == .connected })
        server.unpair(mac.deviceID)
        #expect(registry.devices.isEmpty)
        #expect(await until { server.connected.isEmpty })
        let again = LinkClient()
        again.connect(mac, at: endpoint)
        #expect(await until { if case .failed = again.status { true } else { false } })
        client.unfollow(); again.unfollow()
    }

    @Test func fileRegistryKeepsKeysPrivateAndSurvivesRestart() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paired-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let d = PairedDevice(id: UUID(), name: "Phone", key: Data(repeating: 9, count: 32), pairedAt: Date(timeIntervalSince1970: 1_700_000_000))
        FileDeviceRegistry(url: url).add(d)
        #expect(FileDeviceRegistry(url: url).devices == [d])
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }
}
