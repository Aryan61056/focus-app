import Foundation
import Observation
import FocusBrain
import FocusJudge
import SwiftUI

public struct Presence: Equatable, Sendable { public var state: String; public var reason: String? }
public struct Surface: Equatable, Sendable { public var kind: String; public var severity: Int; public var at: Double }
public struct TimerState: Equatable, Sendable { public var seconds = 0.0, running = false, visible = false, at = 0.0 }
public struct ClockState: Equatable, Sendable { public var seconds = 0.0, running = false, at = 0.0 }
public struct LearnedRule: Equatable, Sendable { public var scope: String, kind: String, keyType: String, key: String }
public struct SessionSummary: Equatable, Sendable {
    public var activeSeconds: Double, offTopicSeconds: Double, unsureSeconds: Double
    public var drifts: Int, interrupts: Int, refusals: Int
}

/// Owns the brain for the app: turns senses into events, effects into UI state, and requests into judge calls.
/// All decisions live in FocusBrain; this class only translates. Judgments run through the two-judge pipeline.
@MainActor @Observable
public final class SessionController {
    // UI state (everything the views read)
    public private(set) var isActive = false
    public private(set) var taskName = ""
    public private(set) var mode = Mode.open
    public private(set) var presence = Presence(state: "off", reason: nil)
    public private(set) var veilTarget = 0
    public private(set) var veilDuration = 0
    public private(set) var offTopic = TimerState()
    public private(set) var clock = ClockState()
    public private(set) var surface: Surface?
    public private(set) var reentryOpen = false
    public private(set) var askResume: String?
    public private(set) var wrapUp = false
    public private(set) var shadowMarks = 0
    public private(set) var learnedRules: [LearnedRule] = []
    public private(set) var summary: SessionSummary?
    public private(set) var currentWindow: WindowSnapshot?
    public private(set) var checkedAt: Double?
    public private(set) var shadow = true

    @ObservationIgnored public var onBringBack: ((String?) -> Void)?
    @ObservationIgnored public var onCue: (() -> Void)?

    @ObservationIgnored private var brain = Brain()
    @ObservationIgnored private let judge: any Judge
    @ObservationIgnored private let now: () -> Double
    @ObservationIgnored private var project = ProjectProfile()
    @ObservationIgnored private var sensitiveUp = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored var totalSeconds = 0.0

    public init(judge: any Judge, now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.judge = judge; self.now = now
    }

    // MARK: session
    public func begin(task: String, mode: Mode = .open, duration: Double? = nil, preset: Preset = .gentle,
                      shadow: Bool = true, project: ProjectProfile = ProjectProfile(), autoTick: Bool = false) {
        guard !isActive else { return }
        self.project = project; self.shadow = shadow
        taskName = task; self.mode = mode; totalSeconds = duration ?? 0
        summary = nil; shadowMarks = 0; learnedRules = []; wrapUp = false; askResume = nil
        var c = SessionConfig(); c.taskId = task; c.mode = mode; c.durationSeconds = duration; c.preset = preset; c.shadow = shadow
        isActive = true
        send(.sessionStart(c))
        if let w = currentWindow { windowChanged(w) }
        if autoTick { startTicking() }
    }

    public func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func nowSeconds() -> Double { now() }

    public func tick() {
        if let s = surface, s.kind != "gate", now() >= s.at + 12 { surface = nil }
        send(.tick)
    }

    // MARK: senses
    public func windowChanged(_ w: WindowSnapshot) {
        currentWindow = w
        guard isActive else { return }
        let m = moment(w)
        if Rules.isSensitive(m) {
            if !sensitiveUp { sensitiveUp = true; send(.sensitiveEntered) }
            return
        }
        if sensitiveUp { sensitiveUp = false; send(.sensitiveLeft) }
        send(.windowChange(WindowChangeInput(windowKey: Keys.window(w), siteKey: Keys.site(w), ruleLabel: Rules.stage1(m).map { Self.brainLabel($0.label) })))
    }

    static func brainLabel(_ l: FocusJudge.Label) -> JudgmentLabel {
        switch l { case .onTask: return .onTask; case .unsure: return .unsure; case .offTask: return .offTask }
    }

    func moment(_ w: WindowSnapshot) -> Moment {
        Moment(task: taskName, app: w.app, windowTitle: w.title, url: w.url, documentPath: w.documentPath, windowText: w.text, project: project)
    }

    // MARK: actions from the UI
    public func act(_ a: UserAction, minutes: Int? = nil) { send(.userAction(a, minutes: minutes)) }
    public func end() { send(.sessionEnd) }

    /// Wait for in-flight judge calls (tests, and orderly shutdown).
    public func waitForJudgments() async {
        while let t = tasks.first { tasks.removeFirst(); await t.value }
    }

    // MARK: brain plumbing
    public func send(_ e: Event) {
        let t = now()
        apply(brain.step(t, e), t)
    }

    func apply(_ effects: [Effect], _ t: Double) {
        for e in effects {
            switch e {
            case .beacon(let s, let r): presence = Presence(state: s, reason: r)
            case .veil(_, let to, let secs): veilTarget = to; veilDuration = secs
            case .offTopicTimer(let s, let r, let v): offTopic = TimerState(seconds: s, running: r, visible: v, at: t)
            case .clock(let s, let r): clock = ClockState(seconds: s, running: r, at: t)
            case .interrupt(let k, let sev, _, _): surface = Surface(kind: k, severity: sev, at: t)
            case .withdraw(let what):
                if what == "reentry" { reentryOpen = false } else { surface = nil }
            case .reentryPrompt: reentryOpen = true
            case .wrapUp: wrapUp = true
            case .askResume(let r): askResume = r
            case .shadowMark: shadowMarks += 1
            case .learnRule(let s, let k, let kt, let key): learnedRules.append(LearnedRule(scope: s, kind: k, keyType: kt, key: key))
            case .bringBack(let w): onBringBack?(w)
            case .cue: onCue?()
            case .requestJudgment(let id, _, _, let wk, _): requestJudgment(id: id, windowKey: wk, observedAt: t)
            case .summary(let a, let o, let u, let d, let i, let r):
                summary = SessionSummary(activeSeconds: a, offTopicSeconds: o, unsureSeconds: u, drifts: d, interrupts: i, refusals: r)
                isActive = false; surface = nil; reentryOpen = false; askResume = nil; wrapUp = false
                timer?.invalidate(); timer = nil
            }
            if case .beacon(let s, _) = e, s != "paused" { askResume = nil }
        }
    }

    private func requestJudgment(id: Int, windowKey: String, observedAt: Double) {
        guard let w = currentWindow, Keys.window(w) == windowKey else { return }
        let m = moment(w)
        let content = Keys.content(w)
        let judge = self.judge
        checkedAt = observedAt
        tasks.append(Task { [weak self] in
            let j = await Pipeline.judge(m, with: judge, useRules: false)
            self?.deliver(j, id: id, observedAt: observedAt, windowKey: windowKey, contentKey: content)
        })
    }

    func deliver(_ j: Judgement, id: Int, observedAt: Double, windowKey: String, contentKey: String) {
        var input = JudgmentInput(requestId: id, observedAt: observedAt, windowKey: windowKey, contentKey: contentKey, label: Self.brainLabel(j.label))
        input.strong = j.label == FocusJudge.Label.offTask          // the two-judge rule already confirmed it (docs/BRAIN-SPEC.md 2.2)
        if j.error != nil { input.flag = .refusal }
        send(.judgment(input))
    }
}

extension SessionController {
    /// Seconds shown on the clock right now: elapsed for Open, remaining for Timed.
    public func clockSeconds() -> Double {
        let c = clock
        guard c.running else { return max(0, c.seconds) }
        let dt = nowSeconds() - c.at
        return max(0, mode == .timed ? c.seconds - dt : c.seconds + dt)
    }

    public func clockText() -> String { Self.format(clockSeconds()) }

    public func offTopicSecondsNow() -> Double { offTopic.seconds + (offTopic.running ? nowSeconds() - offTopic.at : 0) }

    public var isPaused: Bool { presence.state == "paused" }
    public var presenceLabel: String {
        switch presence.state {
        case "paused":
            switch presence.reason { case "break": return "On a break"; case "snooze": return "Snoozed"; case "meeting": return "In a meeting"
            case "idle", "sleep": return "Away"; case "sensitive": return "Not looking"; default: return "Paused" }
        case "drifting": return "Drifting"
        case "watching": return "Not sure"
        case "interrupted": return "Drifting"
        case "recovering": return "Getting back"
        case "off": return "No session"
        default: return "On task"
        }
    }
    /// Green only while on task (direction B); every other state is ink, so color is never the only signal.
    public var ringColor: Color { presence.state == "resting" || presence.state == "recovering" ? Tokens.accent : Tokens.ink }
    public var ringState: RingState {
        switch presence.state {
        case "paused": return presence.reason == "break" ? .breakTime : .paused
        case "drifting", "interrupted": return .drift
        case "watching": return .unsure
        default: return mode == .timed ? .progress(timedProgress()) : .on
        }
    }

    func timedProgress() -> Double {
        // clock holds remaining seconds for Timed; progress needs the total, which the brain does not expose, so use elapsed share
        guard mode == .timed, totalSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - clockSeconds() / totalSeconds))
    }

    static func format(_ s: Double) -> String {
        let n = Int(s.rounded(.down)), h = n / 3600, m = (n % 3600) / 60, sec = n % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
