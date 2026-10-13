import XCTest
import Network
import FocusJudge
import FocusLinkNet
@testable import FocusUI
@testable import FocusLink

/// The whole path with nothing faked but the judge and the clock: a real controller, a real PhoneLink, a real client over a socket.
@MainActor
final class PhoneLinkTests: XCTestCase {
    var controller: SessionController!
    var link: PhoneLink!
    var client: LinkClient!
    var heard: [LinkMessage] = []

    override func setUp() async throws {
        let judge = ScriptedJudge(markers: [])
        controller = SessionController(judge: judge, store: DataStore(), prefs: Preferences(defaults: UserDefaults(suiteName: "focus.link.tests.\(UUID().uuidString)")!))
        link = PhoneLink(registry: MemoryDeviceRegistry(), advertise: false, defaults: UserDefaults(suiteName: "focus.link.tests.\(UUID().uuidString)")!, macName: "Test Mac")
        link.setEnabled(true)
        link.attach(controller)
        try await wait { self.link.isListening }
        link.beginPairing()
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: link.server.port!)!)
        var paired: PairedMac?
        let pairer = LinkClient()
        pairer.pair(endpoint: endpoint, code: link.pairingCode!, deviceName: "Test iPhone") { if case .success(let m) = $0 { paired = m } }
        try await wait { paired != nil }
        client = LinkClient()
        client.onMessage = { [unowned self] in heard.append($0) }
        client.connect(paired!, at: endpoint)
        try await wait { self.client.status == .connected }
    }

    override func tearDown() async throws {
        if controller.isActive { controller.end() }
        client.unfollow(); link.setEnabled(false)
    }

    func wait(_ seconds: Double = 5, _ cond: @escaping () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if cond() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("timed out"); throw CancellationError()
    }

    var lastState: SessionState? { heard.reversed().compactMap { if case .state(let s) = $0 { s } else { nil } }.first }
    func lastResult(_ id: UInt32) -> CommandResult? { heard.compactMap { if case .result(id, let r) = $0 { r } else { nil } }.last }

    func testAPhoneSeesTheMacStateOnConnectAndInsights() async throws {
        try await wait { self.lastState != nil && self.heard.contains { if case .insights = $0 { true } else { false } } }
        XCTAssertEqual(lastState?.phase, .idle)
    }

    func testStartPauseResumeAndEndFromThePhone() async throws {
        client.send(.command(id: 1, .start(task: "Essay outline", minutes: 25)))
        try await wait { self.lastResult(1) == .done && self.controller.isActive }
        try await wait { self.lastState?.task == "Essay outline" }
        XCTAssertEqual(controller.taskName, "Essay outline")
        XCTAssertEqual(controller.mode, .timed)
        XCTAssertEqual(lastState?.timed, true)
        XCTAssertEqual(lastState?.totalSeconds ?? 0, 1500, accuracy: 2)
        XCTAssertEqual(lastState?.clockRunning, true)

        client.send(.command(id: 2, .pause))
        try await wait { self.lastState?.phase == .paused }
        XCTAssertEqual(lastState?.clockRunning, false)
        XCTAssertTrue(controller.isPaused)

        client.send(.command(id: 3, .resume))
        try await wait { self.lastState?.phase == .onTask && self.lastState?.clockRunning == true }

        client.send(.command(id: 4, .takeBreak))
        try await wait { self.lastState?.phase == .onBreak }

        client.send(.command(id: 5, .end))
        try await wait { self.lastState?.phase == .idle && !self.controller.isActive }
        XCTAssertEqual(lastResult(5), .done)
    }

    func testAnOpenSessionHasNoTotal() async throws {
        client.send(.command(id: 1, .start(task: "Reading", minutes: nil)))
        try await wait { self.lastState?.task == "Reading" }
        XCTAssertEqual(lastState?.timed, false)
        XCTAssertEqual(lastState?.totalSeconds, 0)
    }

    func testExtendGrowsTheTotal() async throws {
        client.send(.command(id: 1, .start(task: "Lab", minutes: 10)))
        try await wait { self.lastState?.totalSeconds ?? 0 > 0 }
        client.send(.command(id: 2, .extend(minutes: 5)))
        try await wait { (self.lastState?.totalSeconds ?? 0) > 850 }
        XCTAssertEqual(lastState?.totalSeconds ?? 0, 900, accuracy: 3)
    }

    func testTheMacRefusesWhatItCannotDo() async throws {
        client.send(.command(id: 1, .pause))
        try await wait { self.lastResult(1) != nil }
        XCTAssertEqual(lastResult(1), .refused(reason: "No session is running on your Mac."))

        client.send(.command(id: 2, .start(task: "   ", minutes: nil)))
        try await wait { self.lastResult(2) != nil }
        XCTAssertEqual(lastResult(2), .refused(reason: "Name the task first."))
        XCTAssertFalse(controller.isActive)

        client.send(.command(id: 3, .start(task: "One", minutes: nil)))
        try await wait { self.lastResult(3) == .done }
        client.send(.command(id: 4, .start(task: "Two", minutes: nil)))
        try await wait { self.lastResult(4) != nil }
        XCTAssertEqual(lastResult(4), .refused(reason: "A session is already running on your Mac."))
        XCTAssertEqual(controller.taskName, "One")

        client.send(.command(id: 5, .extend(minutes: 5)))
        try await wait { self.lastResult(5) != nil }
        XCTAssertEqual(lastResult(5), .refused(reason: "This session has no end time to extend."))
    }

    func testAStateChangeMadeOnTheMacReachesThePhone() async throws {
        controller.begin(task: "Started at the Mac", mode: .open, autoTick: false)
        try await wait { self.lastState?.task == "Started at the Mac" }
        controller.act(.pause)
        try await wait { self.lastState?.phase == .paused }
    }

    func testFinishingASessionSendsFreshInsights() async throws {
        let before = heard.filter { if case .insights = $0 { true } else { false } }.count
        controller.begin(task: "Quick", mode: .open, autoTick: false)
        try await wait { self.lastState?.task == "Quick" }
        controller.end()
        try await wait { self.heard.filter { if case .insights = $0 { true } else { false } }.count > before }
    }

    func testTurningTheLinkOffDropsPhones() async throws {
        link.setEnabled(false)
        try await wait { self.link.connected.isEmpty && !self.link.isListening }
        XCTAssertFalse(link.enabled)
    }
}
