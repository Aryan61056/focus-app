import Foundation
import Observation
import FocusBrain
import FocusJudge
import SwiftUI

/// Whether Focus can read window titles. Without Accessibility it can only see which app is in front.
public enum WindowAccess: Equatable, Sendable { case unknown, allowed, appNamesOnly }

/// Whether the live preview can run. It needs Screen Recording, which only the user can grant.
public enum PreviewAccess: Equatable, Sendable { case unknown, allowed, denied }

/// One picture of the window Focus is reading. Held in memory for the running session; never written to disk, never sent to the model.
public struct PreviewFrame: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let image: CGImage
    public let app: String
    public let at: Double
}

/// "Try it" in Settings: after a short countdown, shows what the sensors see right now. Memory only; clears itself.
public enum ProbeState: Equatable, Sendable { case idle, waiting(Int), saw(app: String, title: String, trusted: Bool), nothing }

public struct Presence: Equatable, Sendable { public var state: String; public var reason: String? }
public struct Surface: Equatable, Sendable { public var kind: String; public var severity: Int; public var at: Double }
public struct TimerState: Equatable, Sendable { public var seconds = 0.0, running = false, visible = false, at = 0.0 }
public struct ClockState: Equatable, Sendable { public var seconds = 0.0, running = false, at = 0.0 }
public struct LearnedRule: Equatable, Sendable { public var scope: String, kind: String, keyType: String, key: String }
/// One thing Focus read and concluded. Lives in memory for the running session only; titles are never saved.
public struct Reading: Identifiable, Equatable, Sendable {
    public enum Call: Sendable { case on, unsure, off }
    public enum Source: Sendable { case model, rule, sensitive, skipped }
    public let id = UUID()
    public var at: Double, date: Date
    public var key: String, app: String, title: String
    public var call: Call, source: Source
    public var reason: String
    /// The model refused or errored; Focus treated it as unsure (CLAUDE.md principle 7).
    public var failed = false
    /// Settled by words the window shares with the task, not by the model.
    public var byWords = false
    /// The judge also got the words read from the screen picture, not only the title and address.
    public var sawScreen = false
}

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
    /// "Next step" chosen from the menu bar: shows the same one-line card without waiting for a drift.
    public var manualNextStep = false
    public private(set) var askResume: String?
    public private(set) var wrapUp = false
    public private(set) var shadowMarks = 0
    public private(set) var learnedRules: [LearnedRule] = []
    public private(set) var summary: SessionSummary?
    public private(set) var currentWindow: WindowSnapshot?
    public private(set) var checkedAt: Double?
    public private(set) var shadow = true
    public private(set) var windowAccess = WindowAccess.unknown
    @ObservationIgnored public var onOpenAccessSettings: (() -> Void)?
    /// Bumped by the global hotkey: the window opens the start sheet (or pauses/resumes a running session).
    public private(set) var startRequests = 0
    /// Menu commands (View > Today, Projects, ...) ask the window to switch section. The serial makes repeated requests distinct.
    public private(set) var sectionRequest: (section: AppSection, serial: Int)?
    public func requestSection(_ s: AppSection) { sectionRequest = (s, (sectionRequest?.serial ?? 0) + 1) }
    public func requestStart() { startRequests += 1 }
    public private(set) var judgeStatus = JudgeStatus.unknown
    public func setJudgeStatus(_ s: JudgeStatus) { if judgeStatus != s { judgeStatus = s } }
    @ObservationIgnored public var onOpenModelSettings: (() -> Void)?
    public private(set) var probe = ProbeState.idle
    /// One read of the window in front (set by the app). Nil when Focus itself is in front.
    @ObservationIgnored public var senseNow: (() -> WindowSnapshot?)?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    public private(set) var readings: [Reading] = []
    public private(set) var stats = ReadStats()
    public private(set) var previewFrame: PreviewFrame?
    /// Words read from the latest picture (Apple Vision, on this Mac). Memory only, dropped when the window changes or the session ends.
    public private(set) var screenText = ""
    public var screenWordCount: Int { screenText.split(whereSeparator: { $0.isWhitespace }).count }
    public private(set) var previewAccess = PreviewAccess.unknown
    /// Set while the front window is private or on the never-judged list: nothing is captured then.
    public private(set) var previewHeld: String?
    @ObservationIgnored public var onRequestPreviewAccess: (() -> Void)?

    @ObservationIgnored public var onBringBack: ((String?) -> Void)?
    /// "Back to task": the app name of the window the user was last on task in, so the app can bring it forward. Names only, session only.
    @ObservationIgnored public var onBringBackToApp: ((String) -> Void)?
    @ObservationIgnored var appByWindowKey: [String: String] = [:]
    @ObservationIgnored public var onCue: (() -> Void)?

    @ObservationIgnored private var brain = Brain()
    @ObservationIgnored private let judge: any Judge
    @ObservationIgnored private let now: () -> Double
    @ObservationIgnored public let store: DataStore?
    public let prefs: Preferences
    @ObservationIgnored private let date: () -> Date
    @ObservationIgnored private var projectId: UUID?
    @ObservationIgnored private var sessionId = UUID()
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var segKind: TimelineSegment.Kind?
    @ObservationIgnored private var segStart = 0.0
    @ObservationIgnored private var segments: [TimelineSegment] = []
    @ObservationIgnored private var project = ProjectProfile()
    @ObservationIgnored private var sensitiveUp = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored var totalSeconds = 0.0

    /// Seconds on a clock that keeps counting while the Mac sleeps. ProcessInfo.systemUptime stops during sleep (on the dev Mac it was 92,000 s
    /// behind), which made a night's sleep look like a second, so "ask to resume after a long sleep" never fired.
    public nonisolated static let clock: @Sendable () -> Double = { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1e9 }

    public init(judge: any Judge, store: DataStore? = nil, prefs: Preferences? = nil, now: @escaping () -> Double = SessionController.clock, date: @escaping () -> Date = Date.init) {
        self.judge = judge; self.store = store; self.now = now; self.date = date
        self.prefs = prefs ?? Preferences(defaults: UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!)
    }

    // MARK: session
    public func begin(task: String, mode: Mode = .open, duration: Double? = nil, preset: Preset? = nil,
                      shadow: Bool? = nil, project: ProjectProfile = ProjectProfile(), projectId: UUID? = nil, autoTick: Bool = false) {
        guard !isActive else { return }
        var profile = project
        var pid = projectId
        if let store {
            let p = pid.flatMap { store.project($0) } ?? store.projectNamed(task)
            pid = p.id; profile = p.profile
            if !p.context.isEmpty { profile.context = p.context }   // the judge reads profile.context; Projects edits Project.context
        }
        let shadow = shadow ?? prefs.practiceActive
        self.project = profile; self.projectId = pid; self.shadow = shadow
        sessionId = UUID(); startedAt = date(); segments = []; segKind = nil; segStart = now()
        taskName = task; self.mode = mode; totalSeconds = duration ?? 0
        summary = nil; shadowMarks = 0; learnedRules = []; wrapUp = false; askResume = nil; readings = []; appByWindowKey = [:]; stats = ReadStats(); previewFrame = nil; previewHeld = nil; screenText = ""
        var c = SessionConfig(); c.taskId = task; c.mode = mode; c.durationSeconds = duration; c.preset = preset ?? prefs.preset; c.shadow = shadow
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
    /// Ask "too quiet, about right, too loud" once, after the first finished session in which Focus actually spoke up (not practice).
    public var askLoudness: Bool { !prefs.loudnessAsked && !shadow && (summary?.interrupts ?? 0) > 0 }

    /// One hint, once: during a session where the model is mostly unsure and the project has no description, say what helps.
    public var showContextTip: Bool {
        guard isActive, !prefs.contextTipDismissed, stats.model >= 5, stats.unsure * 10 >= stats.model * 6 else { return false }
        return (projectForNote?.context ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func setWindowAccess(_ a: WindowAccess) { if windowAccess != a { windowAccess = a } }
    /// Counts down so the user can switch to another window, then reports what Focus can see there.
    public func runProbe(seconds: Int = 5, tick: UInt64 = 1_000_000_000) {
        probeTask?.cancel()
        probeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for n in stride(from: seconds, to: 0, by: -1) { self.probe = .waiting(n); try? await Task.sleep(nanoseconds: tick); if Task.isCancelled { return } }
            if let w = self.senseNow?() { self.probe = .saw(app: w.app, title: w.title, trusted: self.windowAccess == .allowed) } else { self.probe = .nothing }
            try? await Task.sleep(nanoseconds: tick * 20)
            if !Task.isCancelled { self.probe = .idle }
        }
    }

    public func setPreviewAccess(_ a: PreviewAccess) { if previewAccess != a { previewAccess = a } }

    /// True when a picture may be taken right now: a session runs, the user turned the preview on, and the window is not private.
    public var previewWanted: Bool { isActive && prefs.readScreen && previewHeld == nil }

    /// Accepts a captured picture only if it is still allowed when it arrives (the window may have changed while it was taken).
    public func setPreview(_ image: CGImage, app: String, text: String? = nil) {
        guard previewWanted else { return }
        previewFrame = PreviewFrame(image: image, app: app, at: now())
        guard let text else { return }
        if Rules.looksPrivate(screenText: text) {
            // Looks like a login or payment screen: drop the picture and the words, and read nothing from this window.
            previewHeld = "This looks private. Not read or shown."; previewFrame = nil; dropScreenText()
            return
        }
        // Only attach the words to the window they came from; the judge reads them on its next check.
        guard var w = currentWindow, w.app == app || w.app.isEmpty else { return }
        screenText = text
        if w.text != text { w.text = text; currentWindow = w }
    }

    private func dropScreenText() {
        screenText = ""
        if var w = currentWindow, !w.text.isEmpty { w.text = ""; currentWindow = w }
    }

    public func clearPreview() { previewFrame = nil; dropScreenText() }


    public func windowChanged(_ w: WindowSnapshot) {
        currentWindow = w; screenText = ""
        if isActive { appByWindowKey[Keys.window(w)] = w.app }
        guard isActive else { return }
        let m = moment(w)
        previewHeld = nil
        if Rules.isSensitive(m) {
            previewHeld = "Private window. Not captured."; previewFrame = nil
            if !sensitiveUp { sensitiveUp = true; send(.sensitiveEntered); record(Reading(at: now(), date: date(), key: "sensitive", app: "", title: "", call: .unsure, source: .sensitive, reason: "A private window. Focus did not read it.")) }
            return
        }
        if sensitiveUp { sensitiveUp = false; send(.sensitiveLeft) }
        let hit = Rules.stage1(m)
        if hit == nil, prefs.skipPersonal, Rules.isNeverJudged(m, apps: prefs.neverJudgedApps) {
            // Not read, not sent to the model, not counted as off task. The title is dropped: chat titles are names.
            previewHeld = "On your never-judged list. Not captured."; previewFrame = nil
            record(Reading(at: now(), date: date(), key: Keys.window(w), app: w.app, title: "", call: .unsure, source: .skipped, reason: "Personal messages, music and blank pages are not judged."))
            send(.windowChange(WindowChangeInput(windowKey: Keys.window(w), siteKey: Keys.site(w), ruleLabel: .unsure)))
            return
        }
        if hit == nil, prefs.matchTaskWords, case let shared = Rules.sharedTaskWords(m), !shared.isEmpty {
            var r = Reading(at: now(), date: date(), key: Keys.window(w), app: w.app, title: w.title, call: .on, source: .rule,
                            reason: "Its app name, title or address shares words with your task: \(shared.prefix(3).joined(separator: ", ")).")
            r.byWords = true
            record(r)
            send(.windowChange(WindowChangeInput(windowKey: Keys.window(w), siteKey: Keys.site(w), ruleLabel: .onTask)))
            return
        }
        if hit == nil, Rules.isGeneralPurposeApp(m) {
            previewHeld = "General-purpose app. Not captured."; previewFrame = nil
            record(Reading(at: now(), date: date(), key: Keys.window(w), app: w.app, title: "", call: .unsure, source: .skipped, reason: "\(w.app) is a tool for any kind of work, so the app alone does not say whether it serves your task."))
            send(.windowChange(WindowChangeInput(windowKey: Keys.window(w), siteKey: Keys.site(w), ruleLabel: .unsure)))
            return
        }
        if let hit { record(Reading(at: now(), date: date(), key: Keys.window(w), app: w.app, title: w.title, call: Self.call(hit.label), source: .rule, reason: Self.ruleReason(hit.rule))) }
        send(.windowChange(WindowChangeInput(windowKey: Keys.window(w), siteKey: Keys.site(w), ruleLabel: hit.map { Self.brainLabel($0.label) })))
    }

    static func call(_ l: FocusJudge.Label) -> Reading.Call { switch l { case .onTask: return .on; case .unsure: return .unsure; case .offTask: return .off } }

    static func ruleReason(_ rule: String) -> String {
        switch rule {
        case "always_allow_app": return "You told Focus this app counts for the project."
        case "always_allow_domain": return "You told Focus this site counts for the project."
        case "always_off_app": return "You told Focus this app never counts for the project."
        case "always_off_domain": return "You told Focus this site never counts for the project."
        default: return "It is linked to this project."
        }
    }

    /// Newest first, and a window that is read again replaces its own latest line instead of repeating it.
    func record(_ r: Reading) {
        switch r.source { case .model: stats.model += 1; case .rule: stats.rule += 1; case .skipped: stats.skipped += 1; case .sensitive: break }
        if r.source == .model || r.source == .rule { switch r.call { case .on: stats.onTask += 1; case .unsure: stats.unsure += 1; case .off: stats.offTask += 1 } }
        if let first = readings.first, first.key == r.key, first.call == r.call, first.source == r.source { readings[0].at = r.at; readings[0].date = r.date; readings[0].reason = r.reason; readings[0].sawScreen = readings[0].sawScreen || r.sawScreen; return }
        readings.insert(r, at: 0)
        if readings.count > 12 { readings.removeLast() }
    }

    /// The latest reading, shown as the headline on Today.
    public var latest: Reading? { readings.first }

    static func brainLabel(_ l: FocusJudge.Label) -> JudgmentLabel {
        switch l { case .onTask: return .onTask; case .unsure: return .unsure; case .offTask: return .offTask }
    }

    func moment(_ w: WindowSnapshot) -> Moment {
        Moment(task: taskName, app: w.app, windowTitle: w.title, url: w.url, documentPath: w.documentPath, windowText: w.text, project: project)
    }

    // MARK: actions from the UI
    public func act(_ a: UserAction, minutes: Int? = nil) { send(.userAction(a, minutes: minutes)) }
    public func end() { send(.sessionEnd) }

    /// "What is the next step?": saved on the project (the start sheet shows it next time), then the brain is told it was answered.
    /// The project of the session that just ended (or is running), for the "where to pick up" note on Today.
    public var projectForNote: Project? { store?.project(projectId) }
    public func setProjectNextStep(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let store, let pid = projectId, var p = store.project(pid) { p.nextStep = String(t.prefix(200)); store.update(p) }
    }

    public func saveNextStep(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, let store, let pid = projectId, var p = store.project(pid) { p.nextStep = String(t.prefix(200)); store.update(p) }
        manualNextStep = false
        act(.nextStep)
    }

    /// "Ask Focus about a window": runs the same judge on text the user typed. Nothing is read from the screen.
    public func ask(app: String, title: String, project p: Project) async -> Judgement {
        var profile = p.profile
        if !p.context.isEmpty { profile.context = p.context }
        let m = Moment(task: p.name, app: app, windowTitle: title, url: "", documentPath: "", windowText: "", project: profile)
        return await Pipeline.judge(m, with: judge, useRules: true)
    }

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
            case .beacon(let s, let r): presence = Presence(state: s, reason: r); markSegment(s, t)
            case .veil(_, let to, let secs): veilTarget = to; veilDuration = secs
            case .offTopicTimer(let s, let r, let v): offTopic = TimerState(seconds: s, running: r, visible: v, at: t)
            case .clock(let s, let r): clock = ClockState(seconds: s, running: r, at: t)
            case .interrupt(let k, let sev, _, _): surface = Surface(kind: k, severity: sev, at: t)
            case .withdraw(let what):
                if what == "reentry" { reentryOpen = false } else { surface = nil }
            case .reentryPrompt: reentryOpen = true
            case .wrapUp: wrapUp = true
            case .askResume(let r): askResume = r
            case .shadowMark(_, _, let wk):
                shadowMarks += 1
                store?.addReview(ReviewMoment(sessionId: sessionId, projectId: projectId, at: date(), windowKey: wk, siteKey: currentWindow.map(Keys.site) ?? wk,
                                              reason: readings.first(where: { $0.key == wk && $0.call == .off })?.reason))
            case .learnRule(let s, let k, let kt, let key):
                let rule = LearnedRule(scope: s, kind: k, keyType: kt, key: key)
                learnedRules.append(rule)
                if let store, let pid = projectId { store.apply(rule, to: pid); if let p = store.project(pid) { project = p.profile } }
            case .bringBack(let w):
                onBringBack?(w)
                if let w, let app = appByWindowKey[w], !app.isEmpty { onBringBackToApp?(app) }
            case .cue: onCue?()
            case .requestJudgment(let id, _, _, let wk, _): requestJudgment(id: id, windowKey: wk, observedAt: t)
            case .summary(let a, let o, let u, let d, let i, let r):
                summary = SessionSummary(activeSeconds: a, offTopicSeconds: o, unsureSeconds: u, drifts: d, interrupts: i, refusals: r)
                markSegment("off", t)
                store?.record(SessionRecord(projectId: projectId, task: taskName, timed: mode == .timed, start: startedAt, end: date(), activeSeconds: a,
                                            offTopicSeconds: o, unsureSeconds: u, drifts: d, interrupts: i, refusals: r, shadowMarks: shadowMarks,
                                            segments: segments.filter { $0.seconds >= 1 }, reads: stats))
                prefs.sessionFinished(wasPractice: shadow)
                previewFrame = nil; previewHeld = nil; screenText = ""
                isActive = false; manualNextStep = false; surface = nil; reentryOpen = false; askResume = nil; wrapUp = false
                timer?.invalidate(); timer = nil
            }
            if case .beacon(let s, _) = e, s != "paused" { askResume = nil }
        }
    }

    /// Builds the session timeline (seconds per state, never window titles) from beacon changes.
    private func markSegment(_ beacon: String, _ t: Double) {
        let kind: TimelineSegment.Kind?
        switch beacon {
        case "resting", "recovering": kind = .on
        case "watching": kind = .unsure
        case "drifting", "interrupted": kind = .off
        case "paused": kind = .gap
        default: kind = nil
        }
        if let k = segKind, t > segStart { segments.append(TimelineSegment(k, t - segStart)) }
        segKind = kind; segStart = t
    }

    private func requestJudgment(id: Int, windowKey: String, observedAt: Double) {
        guard let w = currentWindow, Keys.window(w) == windowKey else { return }
        let m = moment(w)
        let content = Keys.content(w)
        let judge = self.judge
        let sawScreen = !m.windowText.isEmpty
        checkedAt = observedAt
        if !prefs.useModel {
            // The user switched the model off: say so, count it as not sure, and never ask the model.
            record(Reading(at: observedAt, date: date(), key: windowKey, app: w.app, title: w.title, call: .unsure, source: .skipped,
                           reason: "The on-device model is switched off in Settings. Focus only follows your rules and matching words."))
            var input = JudgmentInput(requestId: id, observedAt: observedAt, windowKey: windowKey, contentKey: content, label: .unsure)
            input.strong = false
            send(.judgment(input))
            return
        }
        tasks.append(Task { [weak self] in
            let j = await Pipeline.judge(m, with: judge, useRules: false)
            self?.deliver(j, id: id, observedAt: observedAt, windowKey: windowKey, contentKey: content, sawScreen: sawScreen)
        })
    }

    func deliver(_ j: Judgement, id: Int, observedAt: Double, windowKey: String, contentKey: String, sawScreen: Bool = false) {
        if let w = currentWindow, Keys.window(w) == windowKey {
            var r = Reading(at: observedAt, date: date(), key: windowKey, app: w.app, title: w.title, call: Self.call(j.label), source: .model,
                            reason: Self.tidy(j.reason, failed: j.error != nil))
            r.failed = j.error != nil; r.sawScreen = sawScreen
            record(r)
        }
        var input = JudgmentInput(requestId: id, observedAt: observedAt, windowKey: windowKey, contentKey: contentKey, label: Self.brainLabel(j.label))
        input.strong = j.label == FocusJudge.Label.offTask          // the two-judge rule already confirmed it (docs/BRAIN-SPEC.md 2.2)
        if j.error != nil { input.flag = .refusal }
        send(.judgment(input))
    }
}

extension SessionController {
    /// The judge's own words, trimmed to one short line. A refusal never shows its raw text.
    static func tidy(_ reason: String, failed: Bool) -> String {
        if failed { return "Focus could not read this one, so it did nothing." }
        let t = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "No reason given." }
        return t.count > 160 ? String(t.prefix(157)) + "..." : t
    }

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
