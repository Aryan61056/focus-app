import Testing
import Foundation
@testable import FocusLinkWire

/// Runs both halves against each other with no network, the way the transport will.
private func pair(code: PairingCode, entered: PairingCode, name: String = "Test iPhone") -> (phone: PairedMac?, mac: PairedDevice?, failure: HandshakeFailure?) {
    var server = ServerHandshake(macName: "Test Mac", macID: UUID(), code: code, lookup: { _ in nil })
    var client = ClientHandshake(mode: .pair(entered, deviceName: name))
    var toServer: [Handshake] = [client.start()], toClient: [Handshake] = []
    var phone: PairedMac?, mac: PairedDevice?, failure: HandshakeFailure?
    for _ in 0..<6 where !toServer.isEmpty || !toClient.isEmpty {
        let a = toServer; toServer = []
        for m in a { for s in server.handle(m) { switch s { case .send(let x): toClient.append(x); case .paired(let d): mac = d; case .failed(let f): failure = f; case .established: break } } }
        let b = toClient; toClient = []
        for m in b { for s in client.handle(m) { switch s { case .send(let x): toServer.append(x); case .paired(let p): phone = p; case .failed(let f): failure = failure ?? f; case .established: break } } }
    }
    return (phone, mac, failure)
}

private func connect(mac: PairedMac, registry: [UUID: PairedDevice]) -> (client: SecureChannel?, server: SecureChannel?, failure: HandshakeFailure?) {
    var server = ServerHandshake(macName: "Test Mac", macID: mac.macID, code: nil, lookup: { registry[$0] })
    var client = ClientHandshake(mode: .connect(mac))
    var toServer: [Handshake] = [client.start()], toClient: [Handshake] = []
    var c: SecureChannel?, s: SecureChannel?, failure: HandshakeFailure?
    for _ in 0..<6 where !toServer.isEmpty || !toClient.isEmpty {
        let a = toServer; toServer = []
        for m in a { for st in server.handle(m) { switch st { case .send(let x): toClient.append(x); case .established(_, let ch): s = ch; case .failed(let f): failure = f; case .paired: break } } }
        let b = toClient; toClient = []
        for m in b { for st in client.handle(m) { switch st { case .send(let x): toServer.append(x); case .established(let ch): c = ch; case .failed(let f): failure = failure ?? f; case .paired: break } } }
    }
    return (c, s, failure)
}

@Suite struct PairingCodeTests {
    @Test func displayIsSixteenCharsInGroups() {
        let c = PairingCode.random()
        #expect(c.display.count == 19)
        #expect(c.display.split(separator: "-").map(\.count) == [4, 4, 4, 4])
    }
    @Test func roundTripsThroughText() {
        for _ in 0..<200 { let c = PairingCode.random(); #expect(PairingCode(entered: c.display) == c) }
    }
    @Test func forgivesCaseSpacesAndLookAlikes() {
        let c = PairingCode(bytes: Data(repeating: 0, count: 10))   // 0000-0000-0000-0000
        #expect(PairingCode(entered: "oooo iiii llll oooo") == PairingCode(entered: "0000 1111 1111 0000"))   // i and l read as 1
        #expect(PairingCode(entered: "oooo oooo oooo oooo") == c)
        #expect(PairingCode(entered: " 0000-0000 0000-0000 ") == c)
    }
    @Test func rejectsWrongLengthAndLetters() {
        #expect(PairingCode(entered: "ABCD-EFGH") == nil)
        #expect(PairingCode(entered: "ABCD-EFGH-JKMN-PQRSU") == nil)
        #expect(PairingCode(entered: "ABCD-EFGH-JKMN-PQRU") == nil)   // U is not in the alphabet
    }
}

@Suite struct HandshakeTests {
    @Test func pairingGivesBothSidesTheSameKey() throws {
        let code = PairingCode.random()
        let r = pair(code: code, entered: code)
        let phone = try #require(r.phone), mac = try #require(r.mac)
        #expect(phone.key == mac.key)
        #expect(phone.deviceID == mac.id)
        #expect(phone.key.count == 32)
        #expect(mac.name == "Test iPhone")
        #expect(r.failure == nil)
    }
    @Test func wrongCodeIsRefusedAndNothingIsGranted() {
        let r = pair(code: PairingCode.random(), entered: PairingCode.random())
        #expect(r.phone == nil && r.mac == nil)
        #expect(r.failure == .wrongCode)
    }
    @Test func macNotPairingRefusesNewPhones() {
        var server = ServerHandshake(macName: "M", macID: UUID(), code: nil, lookup: { _ in nil })
        var client = ClientHandshake(mode: .pair(.random(), deviceName: "x"))
        let steps = server.handle(client.start())
        #expect(steps.contains { if case .failed(.notPairing) = $0 { true } else { false } })
    }
    @Test func pairedPhoneConnectsAndMessagesFlowBothWays() throws {
        let code = PairingCode.random()
        let r = pair(code: code, entered: code)
        let phone = try #require(r.phone), mac = try #require(r.mac)
        var c = connect(mac: phone, registry: [mac.id: mac])
        var client = try #require(c.client), server = try #require(c.server)
        let down = try server.seal(Data("state".utf8)), up = try client.seal(Data("command".utf8))
        #expect(try client.open(down) == Data("state".utf8))
        #expect(try server.open(up) == Data("command".utf8))
        // And again: counters advance in step.
        let down2 = try server.seal(Data("more".utf8))
        #expect(try client.open(down2) == Data("more".utf8))
        c.failure = nil
    }
    @Test func unknownPhoneIsRejected() throws {
        let code = PairingCode.random()
        let phone = try #require(pair(code: code, entered: code).phone)
        let c = connect(mac: phone, registry: [:])   // the Mac forgot this phone
        #expect(c.client == nil && c.server == nil)
        #expect(c.failure == .unknownDevice)
    }
    @Test func aMacWithTheWrongKeyIsRefusedByThePhone() throws {
        let code = PairingCode.random()
        let r = pair(code: code, entered: code)
        let phone = try #require(r.phone)
        var impostor = try #require(r.mac)
        impostor.key = randomBytes(32)
        let c = connect(mac: phone, registry: [impostor.id: impostor])
        #expect(c.client == nil)
        #expect(c.failure == .badProof)
    }
    @Test func replayedAndTamperedFramesDoNotOpen() throws {
        let code = PairingCode.random()
        let r = pair(code: code, entered: code)
        let phone = try #require(r.phone), mac = try #require(r.mac)
        let c = connect(mac: phone, registry: [mac.id: mac])
        var client = try #require(c.client), server = try #require(c.server)
        let frame = try server.seal(Data("hello".utf8))
        var tampered = frame; tampered[0] ^= 1
        #expect(throws: SecureChannel.Failure.self) { _ = try client.open(tampered) }
        #expect(try client.open(frame) == Data("hello".utf8))
        #expect(throws: SecureChannel.Failure.self) { _ = try client.open(frame) }   // replay
    }
    @Test func eachConnectionHasFreshKeys() throws {
        let code = PairingCode.random()
        let r = pair(code: code, entered: code)
        let phone = try #require(r.phone), mac = try #require(r.mac)
        var a = try #require(connect(mac: phone, registry: [mac.id: mac]).server)
        var b = try #require(connect(mac: phone, registry: [mac.id: mac]).server)
        #expect(try a.seal(Data("x".utf8)) != b.seal(Data("x".utf8)))
    }
}

@Suite struct FrameTests {
    @Test func reassemblesAcrossArbitrarySplits() throws {
        let payloads = [Data("one".utf8), Data(), Data(repeating: 7, count: 5000), Data("last".utf8)]
        let stream = payloads.reduce(Data()) { $0 + FrameCodec.frame($1) }
        var reader = FrameReader(), got: [Data] = []
        var i = 0
        while i < stream.count { let n = min(1 + (i * 7) % 13, stream.count - i); reader.append(stream[i..<i + n]); i += n; while let f = try reader.next() { got.append(f) } }
        #expect(got == payloads)
    }
    @Test func aPeerThatHasNotAuthenticatedMayOnlySendSmallFrames() throws {
        var reader = FrameReader(maxFrame: FrameCodec.maxHandshakeFrame)
        reader.append(FrameCodec.frame(Data(repeating: 1, count: 1000)))
        #expect(try reader.next()?.count == 1000)
        reader.append(FrameCodec.frame(Data(repeating: 1, count: FrameCodec.maxHandshakeFrame + 1)))
        #expect(throws: FrameReader.TooLarge.self) { _ = try reader.next() }
        reader.maxFrame = FrameCodec.maxFrame   // after the handshake the limit is raised
    }
    @Test func refusesAnAbsurdLength() {
        var reader = FrameReader()
        reader.append(Data([0xFF, 0xFF, 0xFF, 0xFF, 1]))
        #expect(throws: FrameReader.TooLarge.self) { _ = try reader.next() }
    }
}

@Suite struct MessageTests {
    @Test func messagesSurviveJSON() throws {
        let msgs: [LinkMessage] = [
            .state(SessionState(phase: .drifting, task: "Calc homework", timed: true, clockSeconds: 1200, clockRunning: true, totalSeconds: 3000, driftStep: 2, note: "Back in 40 s")),
            .insights(Insights(todayOnTaskSeconds: 1800, goalMinutes: 90, streak: 4, week: [.init(day: Date(timeIntervalSince1970: 1_700_000_000), onTaskSeconds: 600, mark: .focus)])),
            .command(id: 9, .start(task: "Essay", minutes: 25)), .command(id: 1, .pause), .command(id: 2, .extend(minutes: 5)),
            .result(id: 9, .refused(reason: "Already running")), .requestState, .requestInsights,
        ]
        for m in msgs { #expect(try LinkCoding.decode(LinkMessage.self, from: LinkCoding.encode(m)) == m) }
    }
}

@Suite struct PairingLinkTests {
    @Test func roundTripsThroughAURL() throws {
        for _ in 0..<50 {
            let link = PairingLink(code: .random(), macID: UUID())
            #expect(PairingLink(url: link.url) == link)
        }
    }
    @Test func hasTheShapeTheCameraAppCanOpen() {
        let url = PairingLink(code: PairingCode(bytes: Data(repeating: 0, count: 10)), macID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!).url
        #expect(url.absoluteString == "focuslink://pair?c=0000000000000000&m=00000000-0000-0000-0000-000000000001")
    }
    @Test func rejectsAnythingElse() {
        for s in ["https://pair?c=0000000000000000&m=00000000-0000-0000-0000-000000000001", "focuslink://other?c=0000000000000000&m=00000000-0000-0000-0000-000000000001",
                  "focuslink://pair?c=0000&m=00000000-0000-0000-0000-000000000001", "focuslink://pair?c=0000000000000000", "focuslink://pair?c=0000000000000000&m=nope"] {
            #expect(PairingLink(url: URL(string: s)!) == nil)
        }
    }
}
