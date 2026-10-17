import Foundation
import Observation
import AppKit
import FocusUI
import FocusBrain
import FocusLinkNet

/// Connects the session controller to paired iPhones. It reads what the controller already publishes and calls the controller's
/// own public actions, so it adds no decisions of its own: a phone can only do what the Mac's own buttons can do.
/// Off until the user turns it on in the iPhone window. Nothing is advertised or listened for while it is off.
@MainActor @Observable
public final class PhoneLink {
    public private(set) var enabled: Bool
    public private(set) var lastError: String?
    public var pairingCode: PairingCode? { server.pairingCode }
    /// What the QR code says. Nil when pairing is not open.
    public var pairingLink: PairingLink? { server.pairingCode.map { PairingLink(code: $0, macID: macID) } }
    /// The phone that paired most recently, until the window is closed or pairing is started again: lets the window say "connected".
    public private(set) var justPaired: PairedDevice?
    public var phones: [PairedDevice] { registry.devices }
    public var connected: [LinkServer.Phone] { server.connected }
    public var isListening: Bool { server.port != nil }

    @ObservationIgnored let server: LinkServer
    @ObservationIgnored private let macID: UUID
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private let registry: any DeviceRegistry
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private weak var controller: SessionController?
    @ObservationIgnored private var lastSignature: Signature?
    @ObservationIgnored private var lastSessionCount = -1
    @ObservationIgnored private var tracking = false
    /// The session length, learned from the clock when a timed session starts (the controller keeps it internal).
    @ObservationIgnored private var totalSeconds = 0.0
    @ObservationIgnored private var lastClockSeconds = 0.0
    @ObservationIgnored private var sessionSeen: Bool = false

    private static let enabledKey = "focus.link.enabled", macIDKey = "focus.link.macID"

    public init(registry: (any DeviceRegistry)? = nil, advertise: Bool = true, defaults: UserDefaults? = nil, macName: String? = nil) {
        // FOCUS_TEST_STORE=<folder> (the app's testing switch) keeps paired phones and the on/off setting out of the real ones.
        let testFolder = ProcessInfo.processInfo.environment["FOCUS_TEST_STORE"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        let reg = registry ?? FileDeviceRegistry(url: testFolder?.appendingPathComponent("paired-phones.json") ?? FileDeviceRegistry.defaultURL)
        let defaults = defaults ?? testFolder.flatMap { UserDefaults(suiteName: "focus-app.test.\($0.lastPathComponent)") } ?? .standard
        self.registry = reg; self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
        let macID = defaults.string(forKey: Self.macIDKey).flatMap(UUID.init) ?? { let id = UUID(); defaults.set(id.uuidString, forKey: Self.macIDKey); return id }()
        self.macID = macID
        server = LinkServer(macName: macName ?? Host.current().localizedName ?? "Mac", macID: macID, registry: reg, advertise: advertise)
        server.onPaired = { [weak self] device in self?.justPaired = device }
        server.onConnected = { [weak self] id in self?.phoneConnected(id) }
        // After sleep the listener and its Bonjour entry can be stale; start them again so the phone finds this Mac without anyone clicking.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.enabled == true { self?.server.restartListening() } }
        }
        server.onMessage = { [weak self] message, id in self?.received(message, from: id) }
    }

    /// Hand over the controller once the app has one. Starts listening if the user had turned the link on.
    public func attach(_ controller: SessionController) {
        self.controller = controller
        // Testing hook: FOCUS_LINK_PAIR_FILE=<path> turns the link on, opens pairing and writes the code there, so a script can pair a phone.
        if let path = ProcessInfo.processInfo.environment["FOCUS_LINK_PAIR_FILE"], !path.isEmpty {
            setEnabled(true)
            Task { @MainActor [weak self] in
                guard let self else { return }
                for _ in 0..<100 where !self.isListening { try? await Task.sleep(for: .milliseconds(50)) }
                self.beginPairing()
                // Two lines: the typed code, then the link the QR code holds.
                try? ((self.pairingCode?.display ?? "") + "\n" + (self.pairingLink?.url.absoluteString ?? "")).write(toFile: path, atomically: true, encoding: .utf8)
            }
        } else if enabled { startListening() }
        track()
        trackPhones()
    }

    /// Keeps the controller's `phoneState` current, so the sidebar card, toolbar button and menu bar row show whether a phone is paired and connected.
    private func trackPhones() {
        guard let controller else { return }
        withObservationTracking {
            let paired = self.phones, live = self.connected
            let name = paired.first { p in live.contains { $0.id == p.id } }?.name
            let state: SessionController.PhoneState = name.map { .connected($0) } ?? (paired.isEmpty ? .none : .paired(paired.count))
            if controller.phoneState != state { controller.phoneState = state }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.trackPhones() }
        }
    }

    public func setEnabled(_ on: Bool) {
        enabled = on; defaults.set(on, forKey: Self.enabledKey)
        if on { startListening() } else { server.stop() }
    }

    /// One step from the person's side: this turns the link on if it was off, starts listening and opens pairing.
    public func beginPairing() {
        if !enabled { setEnabled(true) } else if !isListening { startListening() }
        justPaired = nil
        server.beginPairing()
    }
    public func cancelPairing() { server.endPairing() }
    public func dismissPaired() { justPaired = nil }
    public func remove(_ id: UUID) { server.unpair(id) }

    private func startListening() {
        do { try server.start(); lastError = nil } catch { lastError = "Couldn't start listening for phones." }
    }

    // MARK: Mac to phone
    private struct Signature: Equatable {
        var session: SessionState
    }

    /// Re-run whenever anything the phone shows changes. Observation fires before the change lands, so read on the next turn.
    private func track() {
        guard let controller, !tracking else { return }
        tracking = true
        withObservationTracking {
            _ = self.makeState(controller, liveClock: false)
            _ = controller.store?.sessions.count
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.tracking = false
                self.publish()
                self.track()
            }
        }
    }

    private func publish() {
        guard let controller else { return }
        let state = makeState(controller, liveClock: true)
        var stable = state; stable.clockSeconds = 0
        let sig = Signature(session: stable)
        // The clock moves every second; only a change in what is shown, or in how the clock runs, is worth a message.
        let clockChanged = controller.clock.running != (lastSignature?.session.clockRunning ?? !controller.clock.running)
        if sig != lastSignature || clockChanged || clockJumped(state) {
            lastSignature = sig
            server.send(.state(state))
        }
        lastClockSeconds = state.clockSeconds
        let count = controller.store?.sessions.count ?? 0
        if count != lastSessionCount { lastSessionCount = count; server.send(.insights(insights(controller))) }
    }

    /// The raw clock only changes on an event (start, pause, resume, extend), so a jump in it is one of those.
    private var lastRawClock = ClockSnapshot()
    private struct ClockSnapshot: Equatable { var seconds = -1.0, running = false }
    private func clockJumped(_ state: SessionState) -> Bool {
        guard let c = controller else { return false }
        let raw = ClockSnapshot(seconds: c.clock.seconds, running: c.clock.running)
        defer { lastRawClock = raw }
        return raw != lastRawClock
    }

    private func makeState(_ c: SessionController, liveClock: Bool) -> SessionState {
        guard c.isActive else { return .idle }
        let timed = c.mode == .timed
        let live = liveClock ? c.clockSeconds() : c.clock.seconds
        if timed {
            if !sessionSeen { totalSeconds = live; sessionSeen = true }
            else if liveClock, live > lastClockSeconds + 2, c.clock.running { totalSeconds += live - lastClockSeconds }   // extended
        }
        let phase: SessionState.Phase
        switch c.presence.state {
        case "paused": phase = c.presence.reason == "break" ? .onBreak : .paused
        case "drifting", "interrupted": phase = .drifting
        case "watching": phase = .unsure
        case "recovering": phase = .recovering
        case "off": phase = .idle
        default: phase = .onTask
        }
        return SessionState(sessionID: nil, phase: phase, task: c.taskName, timed: timed, clockSeconds: live, clockRunning: c.clock.running,
                            totalSeconds: timed ? totalSeconds : 0, offTopicSeconds: liveClock ? c.offTopicSecondsNow() : c.offTopic.seconds,
                            offTopicRunning: c.offTopic.running, driftStep: min(3, c.escalationStep.rawValue), practice: c.shadow, note: c.moment?.text)
    }

    private func insights(_ c: SessionController) -> Insights {
        InsightsBuilder.build(store: c.store, prefs: c.prefs, todayOnTaskSeconds: c.todayOnTaskSeconds())
    }

    private func phoneConnected(_ id: UUID) {
        guard let controller else { return }
        sessionSeen = controller.isActive && sessionSeen
        server.send(.state(makeState(controller, liveClock: true)), to: id)
        server.send(.insights(insights(controller)), to: id)
    }

    // MARK: phone to Mac
    private func received(_ message: LinkMessage, from id: UUID) {
        guard let controller else { return }
        switch message {
        case .requestState: server.send(.state(makeState(controller, liveClock: true)), to: id)
        case .requestInsights: server.send(.insights(insights(controller)), to: id)
        case .command(let cid, let command): server.send(.result(id: cid, apply(command, to: controller)), to: id)
        case .state, .insights, .result: break   // a phone never tells the Mac what is going on
        }
    }

    func apply(_ command: Command, to c: SessionController) -> CommandResult {
        func needsSession() -> CommandResult? { c.isActive ? nil : .refused(reason: "No session is running on your Mac.") }
        switch command {
        case .start(let task, let minutes):
            let name = String(task.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            if c.isActive { return .refused(reason: "A session is already running on your Mac.") }
            if name.isEmpty { return .refused(reason: "Name the task first.") }
            let seconds = minutes.map { Double(min(max($0, 1), 600) * 60) }
            sessionSeen = false
            c.begin(task: name, mode: seconds == nil ? .open : .timed, duration: seconds, autoTick: true)
        case .pause: if let r = needsSession() { return r }; c.act(.pause)
        case .resume: if let r = needsSession() { return r }; c.act(.resume)
        case .end: if let r = needsSession() { return r }; c.end()
        case .takeBreak: if let r = needsSession() { return r }; c.act(.breakTime, minutes: NudgeCopy.breakMinutes)
        case .backToTask: if let r = needsSession() { return r }; c.act(.backToTask)
        case .extend(let m):
            if let r = needsSession() { return r }
            guard c.mode == .timed else { return .refused(reason: "This session has no end time to extend.") }
            c.act(.extend, minutes: min(max(m, 1), 60))
        }
        return .done
    }
}
