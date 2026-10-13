// The focus brain: a pure state machine, step(t, event) -> [Effect]. Implements docs/BRAIN-SPEC.md (draft 0.1).
// Section numbers in comments refer to that spec. Places where the spec was ambiguous are marked "impl:".

struct Policy {
    var grace: Double, timerVisibleFrom: Double
    var veilDrift: Int, veilCap: Int
    var confirmAfter: Double
    var interruptKind: String
    var repeatEvery: Double?
    var reentryDefault: Bool

    static func of(_ p: Preset) -> Policy {
        switch p {
        case .gentle:   return Policy(grace: 45, timerVisibleFrom: 60, veilDrift: 0, veilCap: 0, confirmAfter: 180, interruptKind: "notice", repeatEvery: nil, reentryDefault: false)
        case .standard: return Policy(grace: 25, timerVisibleFrom: 0, veilDrift: 30, veilCap: 60, confirmAfter: 75, interruptKind: "card", repeatEvery: 300, reentryDefault: false)
        case .strict:   return Policy(grace: 10, timerVisibleFrom: 0, veilDrift: 40, veilCap: 80, confirmAfter: 45, interruptKind: "gate", repeatEvery: 180, reentryDefault: true)
        }
    }
}

enum Focus { case onTask, drifting, confirmed, persisting, recovering }
enum EvClass { case on, neutral, strong }
enum EvSource { case judgment, rule, cache }

/// Highest priority first (spec 3.3, beacon reason when holds overlap).
enum HoldReason: Int, CaseIterable {
    case user, meeting, sleep, idle, breakTime, snooze, sensitive
    var name: String {
        switch self {
        case .user: return "user"; case .meeting: return "meeting"; case .sleep: return "sleep"; case .idle: return "idle"
        case .breakTime: return "break"; case .snooze: return "snooze"; case .sensitive: return "sensitive"
        }
    }
    var stopsClock: Bool { self != .snooze && self != .sensitive }
}

struct Hold { var reason: HoldReason; var since: Double; var until: Double? }

struct Block {
    var id: Int?
    var onset: Double
    var offAccum: Double
    var runningSince: Double?
    var strongs: [(at: Double, key: String)] = []
    var flagged = false, everFlagged = false, wasConfirmed = false
    var interruptsInBlock = 0
    var interruptDueAt: Double?
    var targetWindow: String?
    var targetSite: String?

    func timer(_ t: Double) -> Double { offAccum + (runningSince == nil ? 0 : t - runningSince!) }
    mutating func pause(at t: Double) { if let r = runningSince { offAccum += t - r; runningSince = nil } }
}

struct Frozen { var block: Block; var returnAt: Double }
struct Evidence { var cls: EvClass; var at: Double; var fromJudgment: Bool }
struct WindowState { var windowKey: String; var siteKey: String; var ruleLabel: JudgmentLabel?; var since: Double }
struct OpenSurface { var kind: String; var at: Double; var windowKey: String }
struct InFlight { var id: Int; var at: Double; var windowKey: String }
struct Segment { var from: Int, to: Int, startAt: Double, seconds: Int }
enum CacheKind { case on, refused }
struct CacheEntry { var key: String; var kind: CacheKind; var at: Double }
struct Stats { var offTopic = 0.0, unsure = 0.0, drifts = 0, interrupts = 0, refusals = 0, nextBlockId = 1 }
struct BeaconState: Equatable { var state: String; var reason: String? }

struct Session {
    var taskId: String
    var mode: Mode
    var duration: Double
    var policy: Policy
    var shadow: Bool
    var reentry: Bool
    var sound: Bool
    var checkScale: Double
    var startedAt: Double
}

public struct Brain {
    // MARK: state (spec 3.1)
    var lastT = 0.0
    var session: Session?
    var holds: [Hold] = []
    var pausedAccum = 0.0
    var pausedSince: Double?
    var wrapUpSent = false
    var focus = Focus.onTask
    var window: WindowState?
    var block: Block?
    var frozen: Frozen?
    var returnPendingSince: Double?
    var recoveringSince = 0.0
    var confirmedAt = 0.0
    var lastEvidence: Evidence?
    var lastOnTaskWindowKey: String?
    var lastResumeAt = 0.0
    var interruptOpen: OpenSurface?
    var reentryOpen = false
    var interruptHistory: [Double] = []
    var sessionRules: [String: String] = [:]
    var cache: [CacheEntry] = []
    var nextCheckAt = Double.infinity
    var onStreak = 0, neutralStreak = 0
    var inFlight: InFlight?
    var nextRequestId = 1
    var powerConstrained = false, powerCritical = false
    var stats = Stats()
    var lastTimerSeconds = 0.0
    var panicVeil = false
    var forceClock = false

    // last emitted presentation (impl: the spec's "before" is what was last emitted, not a recomputation at t)
    var emBeacon = BeaconState(state: "off", reason: nil)
    var seg = Segment(from: 0, to: 0, startAt: 0, seconds: 0)
    var emTimerVisible = false, emTimerRunning = false
    var emClockRunning: Bool?

    var oneShots: [Effect] = []

    public init() {}

    var isHeld: Bool { !holds.isEmpty }
    var policy: Policy { session?.policy ?? Policy.of(.standard) }

    // MARK: entry point (spec 1.1)
    public mutating func step(_ rawT: Double, _ event: Event) -> [Effect] {
        var starting = false
        if case .sessionStart(let cfg) = event {
            guard session == nil else { return [] }
            lastT = max(rawT, lastT)
            startSession(cfg, lastT)
            starting = true
        } else if session == nil {
            return []
        }
        let t = max(rawT, lastT)
        lastT = t
        oneShots = []
        expireInterrupt(t)
        settle(t)
        if session != nil {
            if !starting { apply(event, t) }
            settle(t)
        }
        let fx = oneShots + presentation(t)
        oneShots = []
        panicVeil = false
        forceClock = false
        // stable sort by emission order
        return fx.enumerated().sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }.map { $0.element }
    }

    // MARK: session lifecycle
    mutating func startSession(_ c: SessionConfig, _ t: Double) {
        var p = Policy.of(c.preset)
        let scale = c.checkScale.isFinite && c.checkScale > 0 ? c.checkScale : 1
        if scale != 1 { p.grace = max(8, p.grace * scale); p.confirmAfter = max(25, p.confirmAfter * scale) }
        session = Session(taskId: c.taskId, mode: c.mode, duration: c.durationSeconds ?? 0, policy: p, shadow: c.shadow,
                          reentry: c.reentryPrompt ?? p.reentryDefault, sound: c.sound, checkScale: scale, startedAt: t)
        holds = []; pausedAccum = 0; pausedSince = nil; wrapUpSent = false
        focus = .onTask; window = nil; block = nil; frozen = nil; returnPendingSince = nil
        lastEvidence = nil; lastOnTaskWindowKey = nil; lastResumeAt = t
        interruptOpen = nil; reentryOpen = false; interruptHistory = []; sessionRules = [:]; cache = []
        nextCheckAt = .infinity; onStreak = 0; neutralStreak = 0; inFlight = nil; nextRequestId = 1
        stats = Stats(); lastTimerSeconds = 0
    }

    mutating func endSession(_ t: Double) {
        closeBlock(t)
        closeFrozen()
        withdrawOpen()
        oneShots.append(.summary(activeSeconds: active(t), offTopicSeconds: stats.offTopic, unsureSeconds: stats.unsure,
                                 drifts: stats.drifts, interrupts: stats.interrupts, refusals: stats.refusals))
        session = nil
        holds = []; returnPendingSince = nil; window = nil; inFlight = nil; focus = .onTask
    }

    func active(_ t: Double) -> Double {
        guard let s = session else { return 0 }
        return t - s.startedAt - pausedAccum - (pausedSince == nil ? 0 : t - pausedSince!)
    }

    // MARK: settle (spec 1.1)
    mutating func settle(_ t: Double) {
        for _ in 0..<4 {
            guard session != nil else { return }
            var changed = false

            // S1 hold expiry
            let due = holds.filter { $0.until != nil && $0.until! <= t }
            if !due.isEmpty {
                for h in due { dropHold(h.reason, t) }
                if holds.isEmpty { resume(t) }
                changed = true
            }
            // S2 timed clock
            if let s = session, s.mode == .timed, !holds.contains(where: { $0.reason.stopsClock }) {
                let remaining = s.duration - active(t)
                if remaining <= 120 && !wrapUpSent { wrapUpSent = true; oneShots.append(.wrapUp(remaining: remaining)); changed = true }
                if remaining <= 0 { endSession(t); return }
            }
            // S3 held
            if isHeld { if changed { continue }; return }
            let pol = policy
            // S4 return complete
            if let rp = returnPendingSince, t >= rp + 15 { enterRecovering(t); changed = true }
            // S5 recovering done
            if focus == .recovering && t >= recoveringSince + 5 { focus = .onTask; changed = true }
            // S6 grace
            if focus == .onTask, var b = block, b.timer(t) >= pol.grace {
                if b.id == nil { b.id = stats.nextBlockId; stats.nextBlockId += 1 }
                block = b; focus = .drifting; changed = true
            }
            // S7 confirm
            if focus == .drifting, returnPendingSince == nil, var b = block, b.timer(t) >= pol.confirmAfter,
               hasIndependentPair(b), lastEvidence?.cls == .strong {
                if !b.wasConfirmed {
                    b.wasConfirmed = true; b.interruptDueAt = t
                    focus = .confirmed; confirmedAt = t
                } else {
                    let lastI = interruptHistory.last ?? -Double.infinity
                    b.interruptDueAt = pol.repeatEvery.map { max(t, lastI + $0) }
                    focus = .persisting
                }
                block = b; changed = true
            }
            // S8 interrupt due
            if interruptDue(t) { changed = true }
            // S9 persist
            if focus == .confirmed && t >= confirmedAt + 12 { focus = .persisting; changed = true }
            // S10 cadence
            if cadenceDue(t) { changed = true }

            if !changed { return }
        }
    }

    func hasIndependentPair(_ b: Block) -> Bool {
        let s = b.strongs
        if s.count < 2 { return false }
        for i in 0..<s.count {
            for j in (i + 1)..<s.count {
                let d = s[j].at - s[i].at
                if s[j].key != s[i].key ? d >= 10 : d >= 20 { return true }
            }
        }
        return false
    }

    mutating func enterRecovering(_ t: Double) {
        guard var b = block, let rp = returnPendingSince else { returnPendingSince = nil; return }
        b.pause(at: rp)
        lastTimerSeconds = b.timer(t)
        frozen = Frozen(block: b, returnAt: rp)
        block = nil; returnPendingSince = nil
        focus = .recovering; recoveringSince = t
        if let o = interruptOpen { oneShots.append(.withdraw(what: o.kind)); interruptOpen = nil }
        if b.wasConfirmed && session?.reentry == true {
            reentryOpen = true
            oneShots.append(.reentryPrompt(block: b.id ?? 0))
        }
    }

    // S8 (spec 4.7). Returns true if state changed.
    mutating func interruptDue(_ t: Double) -> Bool {
        guard let s = session, focus == .confirmed || focus == .persisting, returnPendingSince == nil,
              var b = block, let dueAt = b.interruptDueAt, dueAt <= t, lastEvidence?.cls == .strong,
              let wk = window?.windowKey else { return false }
        let pol = s.policy
        if !s.shadow {
            if let open = interruptOpen {
                if open.kind == "gate", let r = pol.repeatEvery { b.interruptDueAt = dueAt + r; block = b; return true }
                return false  // never stacked: wait for the card or notice to expire
            }
            let recent = interruptHistory.filter { $0 > t - 600 && $0 <= t }
            if recent.count >= 2 { b.interruptDueAt = recent.min()! + 600; block = b; return true }
            let severity = b.interruptsInBlock == 0 ? 1 : 2
            oneShots.append(.interrupt(kind: pol.interruptKind, severity: severity, block: b.id ?? 0, windowKey: wk))
            if s.sound { oneShots.append(.cue) }
            interruptOpen = OpenSurface(kind: pol.interruptKind, at: t, windowKey: wk)
            interruptHistory.append(t)
            stats.interrupts += 1
        } else {
            oneShots.append(.shadowMark(block: b.id ?? 0, kind: pol.interruptKind, windowKey: wk))
        }
        b.interruptsInBlock += 1
        b.interruptDueAt = pol.repeatEvery.map { t + $0 }
        block = b
        return true
    }

    // S10 (spec 6.2)
    mutating func cadenceDue(_ t: Double) -> Bool {
        guard let w = window, nextCheckAt <= t, !powerCritical else { return false }
        if let f = inFlight, t - f.at < 15 { return false }
        if sessionRules[w.windowKey] != nil || sessionRules[w.siteKey] != nil { return false }
        if w.ruleLabel == .onTask || w.ruleLabel == .unsure { return false }
        if let c = cacheEntry(w.windowKey), c.kind == .refused, t - c.at < 900 { return false }
        requestJudgment("cadence", urgency: (block?.flagged == true) ? "high" : "normal", t)
        return true
    }

    mutating func requestJudgment(_ reason: String, urgency: String, _ t: Double) {
        guard let w = window else { return }
        let id = nextRequestId; nextRequestId += 1
        inFlight = InFlight(id: id, at: t, windowKey: w.windowKey)
        nextCheckAt = .infinity
        oneShots.append(.requestJudgment(id: id, reason: reason, urgency: urgency, windowKey: w.windowKey, allowVision: !powerConstrained))
    }

    // MARK: holds (spec 3.3)
    mutating func addHold(_ r: HoldReason, until: Double?, _ t: Double) {
        let wasHeld = isHeld
        let wasStopped = holds.contains { $0.reason.stopsClock }
        holds.removeAll { $0.reason == r }
        holds.append(Hold(reason: r, since: t, until: until))
        if !wasStopped && r.stopsClock { pausedSince = t }
        if r == .sensitive {
            if !wasHeld { freezeBlock(t) }
            window = nil
        } else {
            closeBlock(t)
            closeFrozen()
        }
        nextCheckAt = .infinity; inFlight = nil; returnPendingSince = nil; focus = .onTask
        withdrawOpen()
    }

    mutating func dropHold(_ r: HoldReason, _ t: Double) {
        guard holds.contains(where: { $0.reason == r }) else { return }
        let wasStopped = holds.contains { $0.reason.stopsClock }
        holds.removeAll { $0.reason == r }
        if wasStopped && !holds.contains(where: { $0.reason.stopsClock }), let ps = pausedSince {
            pausedAccum += t - ps; pausedSince = nil
        }
        if r == .sensitive { window = nil }
    }

    mutating func removeHold(_ r: HoldReason, _ t: Double) {
        dropHold(r, t)
        if holds.isEmpty { resume(t) }
    }

    mutating func resume(_ t: Double) {
        focus = .onTask
        lastResumeAt = t
        if window != nil { window!.since = t; evaluateWindow(t, reason: "resume") }
    }

    mutating func closeBlock(_ t: Double) {
        if let b = block { lastTimerSeconds = b.timer(t); count(b, t) }
        block = nil
    }
    mutating func closeFrozen() {
        if let f = frozen { lastTimerSeconds = f.block.timer(0); count(f.block, 0) }
        frozen = nil
    }
    mutating func freezeBlock(_ t: Double) {
        guard var b = block else { return }
        b.pause(at: t)
        lastTimerSeconds = b.timer(t)
        frozen = Frozen(block: b, returnAt: t)
        block = nil
    }
    mutating func count(_ b: Block, _ t: Double) {
        guard b.id != nil else { return }
        let tm = b.timer(t)
        if b.everFlagged { stats.offTopic += tm; stats.drifts += 1 } else { stats.unsure += tm }
    }

    mutating func withdrawOpen() {
        if let o = interruptOpen { oneShots.append(.withdraw(what: o.kind)); interruptOpen = nil }
        if reentryOpen { oneShots.append(.withdraw(what: "reentry")); reentryOpen = false }
    }

    mutating func expireInterrupt(_ t: Double) {
        if let o = interruptOpen, o.kind != "gate", t >= o.at + 12 { interruptOpen = nil }
    }

    // MARK: events (spec 2, 4)
    mutating func apply(_ event: Event, _ t: Double) {
        switch event {
        case .sessionStart, .tick: break
        case .sessionEnd: endSession(t)
        case .judgment(let j): onJudgment(j, t)
        case .windowChange(let w): onWindowChange(w, t)
        case .userAction(let a, let minutes): onUserAction(a, minutes, t)
        case .idle: addHold(.idle, until: nil, t)
        case .sleep: addHold(.sleep, until: nil, t)
        case .active: wakeFrom(.idle, t)
        case .wake: wakeFrom(.sleep, t)
        case .meetingStart: addHold(.meeting, until: nil, t)
        case .meetingEnd: if holds.contains(where: { $0.reason == .meeting }) { oneShots.append(.askResume(reason: "meeting")) }
        case .sensitiveEntered: addHold(.sensitive, until: nil, t)
        case .sensitiveLeft: removeHold(.sensitive, t)
        case .powerChange(let c, let k): powerConstrained = c; powerCritical = k
        }
    }

    /// Idle and sleep: a short absence resumes silently, a long one asks (spec 3.3, 300 s).
    mutating func wakeFrom(_ r: HoldReason, _ t: Double) {
        guard let h = holds.first(where: { $0.reason == r }) else { return }
        if t - h.since < 300 { removeHold(r, t) } else { oneShots.append(.askResume(reason: r.name)) }
    }

    mutating func onWindowChange(_ w: WindowChangeInput, _ t: Double) {
        window = WindowState(windowKey: w.windowKey, siteKey: w.siteKey, ruleLabel: w.ruleLabel, since: t)
        if isHeld { return }
        evaluateWindow(t, reason: "window_change")
    }

    func cacheEntry(_ key: String) -> CacheEntry? { cache.first { $0.key == key } }

    mutating func writeCache(_ key: String, _ kind: CacheKind, _ t: Double) {
        cache.removeAll { $0.key == key }
        cache.append(CacheEntry(key: key, kind: kind, at: t))
        if cache.count > 256 {
            var oldest = 0
            for i in 1..<cache.count {
                let a = cache[i], b = cache[oldest]
                if a.at < b.at || (a.at == b.at && a.key.utf8.lexicographicallyPrecedes(b.key.utf8)) { oldest = i }
            }
            cache.remove(at: oldest)
        }
    }

    /// Spec 4.1, also used by resume.
    mutating func evaluateWindow(_ t: Double, reason: String) {
        guard let w = window else { return }
        onStreak = 0; neutralStreak = 0
        if let g = interruptOpen, g.kind == "gate", g.windowKey != w.windowKey {
            oneShots.append(.withdraw(what: "gate")); interruptOpen = nil
        }
        if sessionRules[w.windowKey] != nil || sessionRules[w.siteKey] != nil {
            applyEvidence(.on, observedAt: t, t, w, contentKey: "", source: .rule); return
        }
        if let rl = w.ruleLabel {
            if rl == .onTask { applyEvidence(.on, observedAt: t, t, w, contentKey: "", source: .rule) }
            else if rl == .unsure { applyEvidence(.neutral, observedAt: t, t, w, contentKey: "", source: .rule) }   // "never judged" windows: no model call, never advances past Drifting
            else { applyEvidence(.strong, observedAt: t, t, w, contentKey: "rule:" + w.windowKey, source: .rule) }
            return
        }
        if let c = cacheEntry(w.windowKey), t - c.at < 900 {
            if c.kind == .on { applyEvidence(.on, observedAt: t, t, w, contentKey: "", source: .cache) }
            else { applyEvidence(.neutral, observedAt: t, t, w, contentKey: "", source: .cache) }
            return
        }
        requestJudgment(reason, urgency: "now", t)
    }

    mutating func onJudgment(_ j: JudgmentInput, _ t: Double) {
        guard session != nil, let w = window else { return }
        let isRefusal = j.flag != .none
        if isHeld {
            // Held: ignored, except an ON result still refreshes the cache (never while a sensitive window is up).
            if !holds.contains(where: { $0.reason == .sensitive }), j.windowKey == w.windowKey, !isRefusal, j.label == .onTask, j.source != .rule {
                writeCache(j.windowKey, .on, t)
            }
            return
        }
        guard j.windowKey == w.windowKey, j.observedAt >= w.since, j.observedAt >= lastResumeAt else { return }
        if let le = lastEvidence, le.fromJudgment, j.observedAt < le.at { return }
        if sessionRules[w.windowKey] != nil || sessionRules[w.siteKey] != nil { return }
        if let f = inFlight, j.requestId == nil || j.requestId == f.id { inFlight = nil }

        let cls: EvClass
        if isRefusal {
            stats.refusals += 1
            writeCache(j.windowKey, .refused, t)
            cls = .neutral
        } else {
            switch j.label {
            case .onTask: writeCache(j.windowKey, .on, t); cls = .on
            case .unsure: cls = .neutral
            case .offTask: cls = j.strong ? .strong : .neutral
            }
        }
        applyEvidence(cls, observedAt: j.observedAt, t, w, contentKey: j.contentKey, source: .judgment)
    }

    // MARK: evidence (spec 4.3)
    mutating func applyEvidence(_ c: EvClass, observedAt o: Double, _ t: Double, _ w: WindowState, contentKey: String, source: EvSource) {
        if c == .on { lastOnTaskWindowKey = w.windowKey }
        switch focus {
        case .recovering:
            if c != .on { focus = .onTask; evidenceWhileOnTask(c, o, t, w, contentKey) }
        case .onTask:
            evidenceWhileOnTask(c, o, t, w, contentKey)
        case .drifting, .confirmed, .persisting:
            evidenceWhileDrifting(c, o, t, w, contentKey)
        }
        lastEvidence = Evidence(cls: c, at: o, fromJudgment: source == .judgment)
        scheduleNext(c, source, t)
    }

    mutating func startBlock(_ o: Double) {
        if let f = frozen, o - f.returnAt <= 120 {
            var b = f.block
            b.runningSince = o; b.strongs = []; b.flagged = false
            block = b; frozen = nil
        } else {
            closeFrozen()
            block = Block(id: nil, onset: o, offAccum: 0, runningSince: o)
        }
    }

    mutating func addStrong(_ o: Double, _ w: WindowState, _ key: String) {
        block!.flagged = true; block!.everFlagged = true
        if focus == .onTask || focus == .drifting { block!.strongs.append((at: o, key: key)) }
        block!.targetWindow = w.windowKey; block!.targetSite = w.siteKey
    }

    mutating func evidenceWhileOnTask(_ c: EvClass, _ o: Double, _ t: Double, _ w: WindowState, _ key: String) {
        switch c {
        case .on:
            if let b = block { lastTimerSeconds = b.timer(t); block = nil }   // a candidate that never reached grace is dropped
        case .neutral:
            if block == nil { startBlock(o) }
        case .strong:
            if block == nil { startBlock(o) }
            addStrong(o, w, key)
        }
    }

    mutating func evidenceWhileDrifting(_ c: EvClass, _ o: Double, _ t: Double, _ w: WindowState, _ key: String) {
        switch c {
        case .on:
            if returnPendingSince == nil {
                returnPendingSince = t
                block?.pause(at: t)
                block?.strongs = []
            }
        case .neutral:
            cancelReturn(o)
        case .strong:
            cancelReturn(o)
            addStrong(o, w, key)
        }
    }

    mutating func cancelReturn(_ o: Double) {
        guard let rp = returnPendingSince else { return }
        block?.runningSince = max(o, rp)
        returnPendingSince = nil
    }

    /// Spec 6.2: when to ask again.
    mutating func scheduleNext(_ c: EvClass, _ source: EvSource, _ t: Double) {
        if c == .on {
            if source == .cache { onStreak = 3 } else if source == .judgment { onStreak += 1 }
        }
        var interval: Double?
        if (focus == .confirmed || focus == .persisting) && returnPendingSince == nil { interval = 30 }
        else if returnPendingSince != nil { interval = 10 }
        else if c == .on && source != .judgment && source != .cache { interval = nil }          // rule: deterministic
        else if c == .on && source == .cache { interval = 90 }
        else if c == .on { interval = [30.0, 60.0, 90.0][min(onStreak, 3) - 1] }
        else if c == .strong || block?.flagged == true { interval = 10 }
        else { neutralStreak += 1; interval = [10.0, 20.0, 40.0, 60.0][min(neutralStreak, 4) - 1] }
        let scale = session?.checkScale ?? 1
        if let i = interval { nextCheckAt = t + max(4, i * scale) * (powerConstrained ? 2 : 1) } else { nextCheckAt = .infinity }
    }

    // MARK: user actions (spec 2.3)
    mutating func onUserAction(_ a: UserAction, _ minutes: Int?, _ t: Double) {
        switch a {
        case .pause: addHold(.user, until: nil, t)
        case .resume:
            guard isHeld else { return }
            for h in holds where h.reason != .sensitive { dropHold(h.reason, t) }
            if holds.isEmpty { resume(t) }
        case .snooze: addHold(.snooze, until: minutes.map { t + 60 * Double($0) }, t)
        case .breakTime: addHold(.breakTime, until: t + 60 * Double(minutes ?? 5), t)
        case .extend:
            guard var s = session, s.mode == .timed else { return }
            s.duration += 60 * Double(minutes ?? 5)
            session = s
            forceClock = true
            if s.duration - active(t) > 120 { wrapUpSent = false }
        case .end: endSession(t)
        case .thatWasFine:
            let (w, _) = target()
            forgive(t, rule: ("allow", w), key: w, scope: "project", kind: "allow", keyType: "window", ruleKey: w)
        case .markRelevant:
            let (w, s) = target()
            forgive(t, rule: ("allow", s), key: w, scope: "project", kind: "allow", keyType: "site", ruleKey: s)
        case .ignoreWindow:
            let (w, _) = target()
            forgive(t, rule: ("ignore", w), key: w, scope: "session", kind: "ignore", keyType: "window", ruleKey: w)
        case .markOffTask:
            if let s = window?.siteKey { oneShots.append(.learnRule(scope: "project", kind: "deny", keyType: "site", key: s)) }
        case .backToTask:
            if let o = interruptOpen { oneShots.append(.withdraw(what: o.kind)); interruptOpen = nil }
            oneShots.append(.bringBack(windowKey: lastOnTaskWindowKey))
        case .dismiss:
            if let o = interruptOpen { oneShots.append(.withdraw(what: o.kind)); interruptOpen = nil }
            else if reentryOpen { oneShots.append(.withdraw(what: "reentry")); reentryOpen = false }
        case .nextStep:
            if reentryOpen { oneShots.append(.withdraw(what: "reentry")); reentryOpen = false }
        case .panic:
            addHold(.user, until: nil, t)
            panicVeil = true
        }
    }

    func target() -> (window: String, site: String) {
        let w = block?.targetWindow ?? window?.windowKey ?? ""
        let s = block?.targetSite ?? window?.siteKey ?? w
        return (w, s)
    }

    /// Spec 4.8.
    mutating func forgive(_ t: Double, rule: (String, String), key: String, scope: String, kind: String, keyType: String, ruleKey: String) {
        if let b = block { lastTimerSeconds = b.timer(t) } else if let f = frozen { lastTimerSeconds = f.block.timer(0) }
        block = nil; frozen = nil; returnPendingSince = nil; focus = .onTask; lastEvidence = nil
        sessionRules[ruleKey] = rule.0
        writeCache(key, .on, t)
        nextCheckAt = .infinity
        withdrawOpen()
        oneShots.append(.learnRule(scope: scope, kind: kind, keyType: keyType, key: ruleKey))
    }

    // MARK: presentation (spec 5.1)
    func beaconNow() -> BeaconState {
        guard let s = session else { return BeaconState(state: "off", reason: nil) }
        if let top = holds.map({ $0.reason }).min(by: { $0.rawValue < $1.rawValue }) { return BeaconState(state: "paused", reason: top.name) }
        if s.shadow { return BeaconState(state: "resting", reason: nil) }
        switch focus {
        case .onTask: return BeaconState(state: "resting", reason: nil)
        case .drifting: return BeaconState(state: block?.flagged == true ? "drifting" : "watching", reason: nil)
        case .confirmed, .persisting: return BeaconState(state: "interrupted", reason: nil)
        case .recovering: return BeaconState(state: "recovering", reason: nil)
        }
    }

    static func level(_ s: Segment, _ t: Double) -> Int {
        if s.seconds == 0 || t - s.startAt >= Double(s.seconds) { return s.to }
        let elapsed = t - s.startAt
        if s.to >= s.from { return s.from + Int(((Double(s.to - s.from) * elapsed) / Double(s.seconds)).rounded(.down)) }
        return s.from - Int(((Double(s.from - s.to) * elapsed) / Double(s.seconds)).rounded(.down))
    }

    func veilTarget(_ t: Double) -> Int {
        guard let s = session, !isHeld, !s.shadow else { return 0 }
        if returnPendingSince != nil { return Brain.level(seg, t) }
        switch focus {
        case .drifting: return block?.flagged == true ? s.policy.veilDrift : 0
        case .confirmed, .persisting: return s.policy.veilCap
        default: return 0
        }
    }

    mutating func presentation(_ t: Double) -> [Effect] {
        var fx: [Effect] = []
        let b = beaconNow()
        if b != emBeacon { fx.append(.beacon(state: b.state, reason: b.reason)); emBeacon = b }

        let target = veilTarget(t)
        if target != seg.to {
            let from = Brain.level(seg, t)
            let secs = target == 0 ? (panicVeil ? 0 : 5) : abs(target - from)   // impl: abs, 1 %/s either direction
            fx.append(.veil(from: from, to: target, seconds: secs))
            seg = Segment(from: from, to: target, startAt: t, seconds: secs)
        }

        var visible = false, running = false
        if let s = session, !isHeld, !s.shadow, focus == .drifting || focus == .confirmed || focus == .persisting,
           let blk = block, blk.flagged, blk.timer(t) >= s.policy.timerVisibleFrom {
            visible = true
        }
        if let blk = block { running = blk.runningSince != nil }
        if visible != emTimerVisible || (visible && running != emTimerRunning) {
            fx.append(.offTopicTimer(seconds: block?.timer(t) ?? lastTimerSeconds, running: running, visible: visible))
        }
        emTimerVisible = visible; emTimerRunning = running

        if let s = session {
            let run = !holds.contains { $0.reason.stopsClock }
            if emClockRunning == nil || run != emClockRunning! || forceClock {
                let a = active(t)
                fx.append(.clock(seconds: s.mode == .timed ? s.duration - a : a, running: run))
            }
            emClockRunning = run
        } else {
            emClockRunning = nil
        }
        return fx
    }
}
