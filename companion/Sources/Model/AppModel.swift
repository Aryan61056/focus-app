import SwiftUI
import Observation
import FocusLinkNet

/// Everything the screens read. One source of truth for "what is the Mac doing", whether that is a real Mac or the demo.
@MainActor @Observable
final class AppModel {
    enum Connection: Equatable {
        case unpaired, searching, connecting, connected, offline(String?), demo
        var isLive: Bool { self == .connected || self == .demo }
    }

    private(set) var clock = SessionClock(state: .idle, receivedAt: .now)
    private(set) var insights: Insights?
    private(set) var mac: PairedMac?
    private(set) var isDemo = false
    /// A short, plain line about something the Mac declined or that went wrong. Clears itself.
    private(set) var notice: String?
    /// Bumped each time the Mac moves to a drift, so the phone can tap once.
    private(set) var driftCount = 0

    let client = LinkClient()
    @ObservationIgnored private let store: PairedMacStore
    @ObservationIgnored private let demo = DemoMac()
    @ObservationIgnored private let liveActivity = LiveActivityController()
    @ObservationIgnored private let pickup = PickupReminder()
    @ObservationIgnored private var nextCommandID: UInt32 = 1
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    init(store: PairedMacStore = .keychain, demo startInDemo: Bool = false) {
        self.store = store
        mac = store.load()
        client.onMessage = { [weak self] in self?.receive($0) }
        client.onConnected = { [weak self] in self?.client.send(.requestState); self?.client.send(.requestInsights) }
        demo.onState = { [weak self] in self?.apply($0) }
        demo.onInsights = { [weak self] in self?.insights = $0 }
        demo.onResult = { [weak self] r in if case .refused(let why) = r { self?.show(why) } }
        if startInDemo { startDemo() } else if let mac { client.follow(mac) }
    }

    var state: SessionState { clock.state }

    var connection: Connection {
        if isDemo { return .demo }
        guard mac != nil else { return .unpaired }
        switch client.status {
        case .connected: return .connected
        case .connecting: return .connecting
        case .searching, .idle: return .searching
        case .failed(let why): return .offline(why)
        }
    }

    // MARK: pairing
    /// Tries the code against the chosen Mac. Reports back with nil on success or a plain sentence on failure.
    func pair(with found: LinkClient.FoundMac, code text: String, deviceName: String, done: @escaping (String?) -> Void) {
        guard let code = PairingCode(entered: text) else { return done("That code should be 16 letters and numbers.") }
        client.pair(with: found, code: code, deviceName: deviceName) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let paired):
                guard store.save(paired) else { return done("Paired, but this phone couldn't keep the pairing safe. Try again.") }
                mac = paired; stopDemo()
                client.follow(paired)
                done(nil)
            case .failure(.wrongCode): done("That code isn't right. Check your Mac and try again.")
            case .failure(.notPairing): done("Your Mac isn't showing a code. Choose Pair a phone on the Mac first.")
            case .failure: done("Couldn't reach your Mac. Make sure you're on the same Wi-Fi.")
            }
        }
    }

    func forgetMac() {
        client.unfollow(); store.clear(); mac = nil
        apply(.idle); insights = nil
    }

    #if DEBUG
    /// `-pair <code>` on launch: pair with the first Mac that shows up. For testing the real link without typing.
    func autoPair(code: String) {
        client.browse()
        Task { [weak self] in
            guard let self else { return }
            for _ in 0..<200 where client.found.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
            guard let found = client.found.first else { return show("No Mac found to pair with.") }
            pair(with: found, code: code, deviceName: "Test iPhone") { [weak self] problem in if let problem { self?.show(problem) } }
        }
    }

    /// `-remote-start <task>` on launch: start a 25 minute session once the Mac is connected.
    func autoStart(task: String) {
        Task {
            for _ in 0..<200 where connection != .connected { try? await Task.sleep(for: .milliseconds(100)) }
            start(task: task, minutes: 25)
        }
    }
    #endif

    // MARK: demo
    func startDemo() {
        client.unfollow(); isDemo = true
        apply(.idle); demo.connect()
    }

    func stopDemo() {
        guard isDemo else { return }
        demo.disconnect(); isDemo = false; apply(.idle); insights = nil
        if let mac { client.follow(mac) }
    }

    // MARK: commands
    func start(task: String, minutes: Int?) { send(.start(task: task.trimmingCharacters(in: .whitespacesAndNewlines), minutes: minutes)) }
    func pause() { send(.pause) }
    func resume() { send(.resume) }
    func takeBreak() { send(.takeBreak) }
    func backToTask() { send(.backToTask) }
    func extend(minutes: Int) { send(.extend(minutes: minutes)) }
    func end() { send(.end) }

    private func send(_ c: Command) {
        if isDemo { return demo.handle(c) }
        guard connection == .connected else { return show("Your Mac isn't connected right now.") }
        let id = nextCommandID; nextCommandID &+= 1
        client.send(.command(id: id, c))
    }

    // MARK: incoming
    private func receive(_ m: LinkMessage) {
        switch m {
        case .state(let s): apply(s)
        case .insights(let i): insights = i
        case .result(_, .refused(let why)): show(why)
        case .result, .command, .requestState, .requestInsights: break
        }
    }

    /// The app went to the background: if a session is running, a gentle reminder is scheduled. See PickupReminder.
    func leftApp() { pickup.arm(clock: clock, live: connection.isLive) }
    func cameBack() { pickup.disarm() }

    private func apply(_ s: SessionState) {
        if s.phase == .drifting, clock.state.phase != .drifting { driftCount += 1 }
        if s.isActive, !clock.state.isActive { pickup.askPermissionIfNeeded() }
        clock = SessionClock(state: s, receivedAt: .now)
        liveActivity.sync(clock)
    }

    func show(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.notice = nil }
        }
    }
}
