import SwiftUI
import Observation
import FocusLinkNet
import FocusLinkCloud

/// Everything the screens read. One source of truth for "what is the Mac doing", whether that is a real Mac or the demo.
@MainActor @Observable
final class AppModel {
    enum Connection: Equatable {
        case unpaired, searching, connecting, connected, offline(String?), demo
        var isLive: Bool { self == .connected || self == .demo }
    }

    private(set) var clock = SessionClock(state: .idle, receivedAt: .now)
    /// Insights from the Mac over the local link, the freshest the phone has when it is connected.
    private(set) var insights: Insights?
    /// Insights from the person's iCloud, for when the Mac is off or not on this Wi-Fi.
    let cloud = CloudInsights()
    @ObservationIgnored private var linkInsightsAt: Date?
    private(set) var mac: PairedMac?
    private(set) var isDemo = false
    /// A short, plain line about something the Mac declined or that went wrong. Clears itself.
    private(set) var notice: String?
    /// Bumped each time the Mac moves to a drift, so the phone can tap once.
    private(set) var driftCount = 0

    /// What opening a pairing link (the Mac's QR code) is doing right now.
    enum Linking: Equatable { case idle, working(String), done(String), failed(String) }
    private(set) var linking = Linking.idle
    /// Set when a scan could not finish by itself, so the person can type the code instead.
    var showPairingSheet = false
    private(set) var pendingCode: String?
    /// Bumped on a successful pairing, for a haptic.
    private(set) var pairedCount = 0

    /// One model for the whole process, so a Shortcuts action that wakes the app reads the same state the screens do.
    static let shared = AppModel()

    /// Bumped each time the guard sends the person back to Focus; the screen that welcomes them back listens to it.
    private(set) var guardCount = 0
    var showingGuard = false

    let client = LinkClient()
    /// The apps the person chose to cover while they work.
    let blocker = DistractionBlocker()
    @ObservationIgnored private let store: PairedMacStore
    @ObservationIgnored private let demo = DemoMac()
    @ObservationIgnored private let liveActivity = LiveActivityController()
    @ObservationIgnored private let pickup = PickupReminder()
    @ObservationIgnored private let guardCache = GuardCache()
    @ObservationIgnored private let guardLog = GuardLog()
    /// When the guard last ran and what it decided. Empty until a Shortcuts automation has fired once.
    private(set) var lastGuard: (at: Date, outcome: GuardOutcome)?
    /// True once the Mac has said how things stand on this connection, so the clock can be trusted whatever its age.
    @ObservationIgnored private var heardThisConnection = false
    @ObservationIgnored private var nextCommandID: UInt32 = 1
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    init(store: PairedMacStore = .keychain, demo startInDemo: Bool = false) {
        self.store = store
        mac = store.load()
        lastGuard = guardLog.last()
        client.onMessage = { [weak self] in self?.receive($0) }
        client.onConnected = { [weak self] in self?.heardThisConnection = false; self?.client.send(.requestState); self?.client.send(.requestInsights) }
        demo.onState = { [weak self] in self?.apply($0) }
        demo.onInsights = { [weak self] in self?.insights = $0; self?.linkInsightsAt = .now }
        demo.onResult = { [weak self] r in if case .refused(let why) = r { self?.show(why) } }
        if startInDemo { startDemo() } else if let mac { client.follow(mac) }
    }

    var state: SessionState { clock.state }

    /// What the Insights tab shows: the Mac's own numbers while connected, otherwise the newer of the last ones it sent and iCloud's.
    var displayedInsights: Insights? { source.insights }
    /// When the shown numbers are from iCloud and not live, the moment they were worked out. Nil when they are live.
    var insightsAsOf: Date? { source.asOf }

    private var source: (insights: Insights?, asOf: Date?) {
        if isDemo { return (insights, nil) }
        if connection == .connected, let insights { return (insights, nil) }
        if let snap = cloud.snapshot {
            if let at = linkInsightsAt, at > snap.asOf, let insights { return (insights, nil) }
            return (snap.shown(), snap.asOf)
        }
        return (insights, nil)
    }

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

    /// The Mac's QR code, opened by the Camera app: find that Mac, pair with the code in the link, and say what happened.
    func open(_ url: URL) {
        guard let link = PairingLink(url: url) else { return show("That isn't a Focus pairing code.") }
        if mac?.macID == link.macID, connection == .connected { return }   // already paired with this Mac
        pendingCode = link.code.display
        linking = .working("Looking for your Mac…")
        client.browse()
        Task { [weak self] in
            guard let self else { return }
            var found: LinkClient.FoundMac?
            for _ in 0..<150 {   // up to 15 s: the first launch also waits on the Local Network permission
                found = client.found.first { $0.id == link.macID }
                if found != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let found else { return failLink("Couldn't find your Mac. Check that you're on the same Wi-Fi and Focus is open.") }
            linking = .working("Pairing with \(found.name)…")
            pair(with: found, code: link.code.display, deviceName: UIDevice.current.name) { [weak self] problem in
                guard let self else { return }
                if let problem { failLink(problem) } else {
                    pairedCount += 1; pendingCode = nil
                    linking = .done(found.name)
                    Task { try? await Task.sleep(for: .seconds(2.5)); if case .done = self.linking { self.linking = .idle } }
                }
            }
        }
    }

    private func failLink(_ why: String) {
        linking = .failed(why)
        showPairingSheet = true
    }

    func dismissLinking() { linking = .idle }

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
        case .state(let s): heardThisConnection = true; apply(s)
        case .insights(let i): insights = i; linkInsightsAt = .now
        case .result(_, .refused(let why)): show(why)
        case .result, .command, .requestState, .requestInsights: break
        }
    }

    /// The app went to the background: if a session is running, a gentle reminder is scheduled. See PickupReminder.
    func leftApp() { pickup.arm(clock: clock, live: connection.isLive) }
    func cameBack() { pickup.disarm(); Task { await cloud.refresh() } }

    private func apply(_ s: SessionState) {
        if s.phase == .drifting, clock.state.phase != .drifting { driftCount += 1 }
        if s.isActive, !clock.state.isActive { pickup.askPermissionIfNeeded() }
        clock = SessionClock(state: s, receivedAt: .now)
        if !isDemo { guardCache.save(clock) }
        liveActivity.sync(clock)
        blocker.sync(s, canBlock: !isDemo)
    }

    // MARK: guard
    /// Should opening a distracting app bounce the person back to Focus? Asks the Mac if it can be reached in a moment, and
    /// otherwise trusts the last thing it said, as long as that is recent. Leans toward "yes" when unsure: that is the point.
    func guardCheck(now: Date = .now, record: Bool = true) async -> GuardOutcome {
        let outcome = await decideGuard()
        if record { guardLog.record(outcome); lastGuard = guardLog.last() }
        return outcome
    }

    private func decideGuard() async -> GuardOutcome {
        guard blocker.enabled else { return .switchedOff }
        guard !isDemo else { return .demo }
        guard mac != nil else { return .notPaired }
        let deadline = Date().addingTimeInterval(GuardRules.patience)
        while !(connection == .connected && heardThisConnection), Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        let live = connection == .connected && heardThisConnection
        guard let known = live ? clock : guardCache.load() else { return .noSession }
        return GuardRules.shouldBounce(known, live: live, now: Date()) ? .sentBack : .noSession
    }

    func showGuard() { guardCount += 1; showingGuard = true }

    func show(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.notice = nil }
        }
    }
}
