import Foundation
import FocusJudge

// Everything around the warning that is not the warning itself: the heads-up before it, the small banner over the window you drifted into,
// the cues outside the app (menu bar, Dock, trackpad, voice), the friction before going back, the scheduled rhythm, and how hard Hushd
// pushes at different times of day. All of it lives in the controller layer, so the brain and its golden traces are unchanged.
// Pure types and rules here; SessionController+Cues.swift wires them to the session.

// MARK: heads-up before a warning

/// Watches the last few readings for the shape of a rabbit hole, before the brain has confirmed a drift.
/// Two shapes count: several off-topic readings in a row, or hopping between windows that are all off or not sure.
/// Owner, 2026-10-13: wants Hushd to speak up earlier. The cost is more mistaken heads-ups, so it is only a banner (no sound), it waits
/// five minutes between heads-ups, and "It's part of it" teaches Hushd the window.
public struct DriftWatch: Equatable, Sendable {
    public struct Point: Equatable, Sendable { public var at: Double; public var call: Reading.Call; public var key: String }
    public var span = 120.0, cooldown = 300.0
    public private(set) var points: [Point] = []
    public private(set) var lastNoticeAt: Double?
    public init() {}

    public mutating func note(call: Reading.Call, key: String, at t: Double) {
        points.append(Point(at: t, call: call, key: key))
        points.removeAll { t - $0.at > span }
        if points.count > 24 { points.removeFirst(points.count - 24) }
    }

    public mutating func markNoticed(at t: Double) { lastNoticeAt = t }

    /// Forget the readings (back on task, or a new session). The cooldown stays so a flicker cannot bring the notice straight back.
    public mutating func clearReadings() { points = [] }
    public mutating func reset() { points = []; lastNoticeAt = nil }

    public func looksLikeARabbitHole(at t: Double) -> Bool {
        if let l = lastNoticeAt, t - l < cooldown { return false }
        let recent = points.filter { t - $0.at <= span }
        guard recent.count >= 3, recent.suffix(2).allSatisfy({ $0.call != .on }) else { return false }
        let away = recent.filter { $0.call != .on }, on = recent.count - away.count
        guard away.count >= 3, away.count >= 2 * on else { return false }
        // One window judged again and again is a drift the brain is already following. Several different windows that are all off or
        // not sure is the hopping the brain never confirms on its own.
        return away.contains { $0.call == .off } || Set(away.map(\.key)).count >= 3
    }
}

/// The small banner over the window you are in: the one place a prompt reaches you wherever you are working. `early` is the heads-up;
/// `reminder` stays from the warning until you are back; `checkIn` asks the ladder's question; `rhythm` is a scheduled check-in or break.
/// The check-in and the schedule used to show only as cards inside Hushd's own window, which is behind the app you are in, so they
/// could not be answered without finding Hushd first.
public struct Banner: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case early, reminder, checkIn, rhythm }
    public var kind: Kind
    public var at: Double
}

// MARK: cues outside the app

/// Things worth a cue. The controller decides which channels each one uses from the user's switches.
public enum CueEvent: Equatable, Sendable {
    case headsUp, warning, checkIn, pauseScreen, enforce, friction, rhythmCheckIn, breakDue
    /// The strongest buzz: the pause screen and the last step.
    var strong: Bool { self == .pauseScreen || self == .enforce }
    /// The loud ones: a nudge you ignored, or something that needs an answer. The heads-up stays light.
    var firm: Bool { self != .headsUp }
    /// The Dock bounce is for what happens while you are in another app.
    var bouncesDock: Bool { self != .headsUp }
    var speaks: Bool { self != .headsUp && self != .friction }
}

public enum HapticPattern: Equatable, Sendable {
    /// Three quick taps.
    case light
    /// A run of seven taps, about a second.
    case firm
    /// A long run of twelve taps, close together: the pause screen and the last step.
    case strong
    /// Seconds between taps of a pattern, so a player can schedule them. The Mac gives apps one tap strength, so a stronger
    /// buzz is more taps closer together, not a harder tap.
    public var taps: [Double] {
        switch self {
        case .light: return [0, 0.1, 0.2]
        case .firm: return (0..<7).map { Double($0) * 0.1 }
        case .strong: return (0..<12).map { Double($0) * 0.08 }
        }
    }
}

/// How the menu bar icon reads: plain, a soft tint for a heads-up or a prompt, or the warm tint and a slow pulse while you are away.
public enum MenuCue: Equatable, Sendable { case none, headsUp, away }

// MARK: the shield: a screen that has to be answered

/// A screen that covers the display until it is answered. Three kinds: the pause screen after a warning went unanswered, the same site
/// opening again after a pause screen, and a claim that a window Hushd flagged is really part of the task.
/// The only ways through are going back to the task, or explaining the window in words that Hushd checks against the window itself.
public struct Shield: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case pause, friction, claim }
    public var kind: Kind
    public var app: String
    public var siteKey: String
    public var since: Double
    /// Explaining opens at this time. Until then only "Back to task" works.
    public var waitUntil: Double
    /// The explanation form is open.
    public var asking = false
    /// The on-device model is reading the window against the explanation.
    public var checking = false
    /// Why the last explanation did not pass, or what is wrong with it.
    public var message: String?
    public var attemptsLeft = Shield.attempts
    public static let attempts = 2
    /// Two failed explanations lock the way through for this long.
    /// The first lock lasts this long and each later one doubles, up to half an hour. Explaining itself never waits; a bad explanation is what costs time.
    public static let lockSeconds = 300.0
    public static func lockSeconds(after locks: Int) -> Double { min(1800, lockSeconds * pow(2, Double(max(0, locks)))) }
    /// With "hold to go back" on, press and hold Back to task this long. Letting go starts over.
    public static let backHoldSeconds = 3.0
    /// How long a cover may sit unanswered before Hushd acts on the site.
    public static let frictionIdle = 30.0
    /// How long an accepted explanation holds for that one page: 8 minutes, then 5, 3 and 2. The more you lean on it, the less it buys.
    public static func passSeconds(afterClaims n: Int) -> Double { [480, 300, 180, 120][min(max(0, n), 3)] }
    /// The model must be at least this sure the page serves the task: 80, then 85, 90, up to 95 for later explanations.
    public static func minConfidence(afterClaims n: Int) -> Int { min(95, Verification.minConfidence + 5 * max(0, n)) }
    /// Explanations Hushd will accept in one session. After that, the only way back is the task.
    public static let claimCap = 8
}

// MARK: scheduled rhythm

public enum Rhythm: String, CaseIterable, Identifiable, Sendable {
    case off, checkIns, pomodoro
    public var id: String { rawValue }
    public var title: String { switch self { case .off: return "Off"; case .checkIns: return "Check-ins"; case .pomodoro: return "Work and break" } }
    public var detail: String {
        switch self {
        case .off: return "Hushd only speaks up when you drift."
        case .checkIns: return "A short \u{201C}still on task?\u{201D} prompt at a steady interval, even when you are on task."
        case .pomodoro: return "Work for 25 minutes, then a 5 minute break; every fourth break is 15 minutes. The clock stops while you are on a break or paused."
        }
    }
    public static let workMinutes = 25, shortBreak = 5, longBreak = 15, cyclesBeforeLong = 4
    public static let checkInChoices = [15, 25, 45, 60]
    /// Work done when the prompt is due, in seconds.
    public func dueAfter(checkInMinutes: Int) -> Double? {
        switch self { case .off: return nil; case .checkIns: return Double(checkInMinutes) * 60; case .pomodoro: return Double(Self.workMinutes) * 60 }
    }
    /// Minutes of break to offer after `completed` finished work blocks (the block that just ended counts).
    public static func breakMinutes(afterBlock completed: Int) -> Int { completed > 0 && completed % cyclesBeforeLong == 0 ? longBreak : shortBreak }
}

public struct RhythmPrompt: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case checkIn, breakDue(minutes: Int)
        /// The ring a prompt shows: closed for a check-in, a ring with a dot for a break.
        var ring: RingState { if case .breakDue = self { return .breakTime }; return .on }
    }
    public var kind: Kind
    public var at: Double
}

// MARK: pressure through the day

/// How hard Hushd pushes. Easy in the morning, steady when you are on pace for your daily goal, firmer when you are behind it.
/// It changes how quickly Hushd warns and climbs, never what counts as off task, and the app always says which level it is at and why.
public enum DayPressure: Int, Comparable, Sendable {
    case relaxed, steady, behind, wellBehind
    public static func < (a: DayPressure, b: DayPressure) -> Bool { a.rawValue < b.rawValue }

    /// Multiplies the time Hushd waits (smaller is quicker). Applied to the brain's check scale when a session begins, and to the ladder live.
    public var factor: Double { switch self { case .relaxed: return 1.25; case .steady: return 1.0; case .behind: return 0.8; case .wellBehind: return 0.65 } }
    /// Extra seconds the pause screen holds the easy exits.
    public var extraHold: Double { switch self { case .relaxed, .steady: return 0; case .behind: return 5; case .wellBehind: return 10 } }

    /// The working day the pace is measured over. Before `morningUntil` Hushd is easy whatever you have done.
    public static let morningUntil = 12.0, dayStart = 9.0, dayEnd = 18.0

    /// `onTaskSeconds` is today's on-task time so far; `goalMinutes` of 0 means no goal, so no pace.
    public static func level(goalMinutes: Int, onTaskSeconds: Double, at date: Date, calendar cal: Calendar = .current) -> DayPressure {
        guard goalMinutes > 0 else { return .steady }
        let goal = Double(goalMinutes) * 60
        if onTaskSeconds >= goal { return .relaxed }
        let c = cal.dateComponents([.hour, .minute], from: date)
        let hour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        if hour < morningUntil { return .relaxed }
        let expected = min(1, max(0, (hour - dayStart) / (dayEnd - dayStart)))
        let gap = expected - onTaskSeconds / goal
        if gap <= 0 { return .steady }
        return gap <= 0.25 ? .behind : .wellBehind
    }

    public var title: String {
        switch self { case .relaxed: return "Easy"; case .steady: return "Steady"; case .behind: return "Firmer"; case .wellBehind: return "Firmest" }
    }
}

/// A line for Today that says why Hushd is pushing the way it is. Honest and plain: it never hides a change in how firm Hushd is.
public enum PaceCopy {
    public static func line(_ p: DayPressure, goalReached: Bool, behindMinutes: Int) -> String? {
        switch p {
        case .steady: return nil
        case .relaxed: return goalReached ? "You reached today's goal, so Hushd is easy on you now." : "It is early in the day, so Hushd is easy on you."
        case .behind: return "You are a little behind today's goal, so Hushd speaks up sooner."
        case .wellBehind: return behindMinutes > 0 ? "You are about \(behindMinutes) minutes behind today's goal, so Hushd is firmer." : "You are well behind today's goal, so Hushd is firmer."
        }
    }
}

// MARK: ladder and wording

extension EscalationPlan {
    /// The same ladder, quicker (factor under 1) or slower, with the pause screen's hold lengthened. Steps stay in order and never get closer than a few seconds.
    public func scaled(by factor: Double, extraHold: Double = 0) -> EscalationPlan {
        let f = max(0.3, factor)
        let c = max(12, checkInAfter * f)
        let p = max(c + 20, pauseAfter * f)
        let e = max(p + 40, enforceAfter * f)
        return EscalationPlan(checkInAfter: c, pauseAfter: p, enforceAfter: e, enforceEvery: max(40, enforceEvery * f), holdSeconds: holdSeconds + extraHold)
    }
}

/// Words for the new surfaces. Same rules as NudgeCopy: second person, sentence case, no exclamation marks, never the name of what you were looking at.
public enum CueCopy {
    /// Shown on the reminder banner before a Strict round closes the tab, so closing is never a surprise.
    public static let closeWarning = "Hushd will close this tab next."
    public static func bannerTitle(_ kind: Banner.Kind, tone: NudgeTone, task: String, rhythm: RhythmPrompt.Kind? = nil) -> String {
        switch (kind, tone) {
        case (.early, .neutral): return "Still on \(task)?"
        case (.early, .coach): return "Easing away from \(task)?"
        case (.early, .direct): return "Drifting from \(task)?"
        case (.reminder, .neutral): return "Back to \(task)?"
        case (.reminder, .coach): return "\(task) is waiting for you"
        case (.reminder, .direct): return "Back to \(task)"
        case (.checkIn, _): return NudgeCopy.checkInTitle(task: task)
        case (.rhythm, _): return rhythmTitle(rhythm ?? .checkIn, task: task)
        }
    }

    /// The short line under the banner's title: what Hushd saw, in a few words and numbers, never the name of the window.
    public static func headsUpMeta(away: Int, of total: Int) -> String { "\(away) of the last \(total) reads off task" }
    public static let reminderMeta = "Off task"
    public static let checkInMeta = "Read again: still off task"
    public static func rhythmMeta(_ k: RhythmPrompt.Kind, checkInMinutes: Int) -> String {
        switch k {
        case .checkIn: return "Check-in every \(checkInMinutes) min"
        case .breakDue: return "\(Rhythm.workMinutes) min of work done"
        }
    }
    /// The steps of the ladder, for the dots on the banner and what VoiceOver says about them.
    public static let ladderSteps = ["warning", "check-in", "pause screen", "Hushd acts on the window"]
    public static func ladderLabel(_ step: EscalationStep) -> String {
        let i = step.rawValue
        let next = i + 1 < ladderSteps.count ? " Next, \(ladderSteps[i + 1])." : ""
        return "Step \(i + 1) of \(ladderSteps.count), \(ladderSteps[i]).\(next)"
    }

    public static func shieldTitle(_ k: Shield.Kind) -> String {
        switch k { case .pause: return "Take a moment"; case .friction: return "This is where you drifted"; case .claim: return "Check this window" }
    }
    public static func shieldBody(_ k: Shield.Kind, tone: NudgeTone, task: String, longDetour: Bool) -> String {
        switch k {
        case .pause: return NudgeCopy.gateBody(tone: tone, task: task, longDetour: longDetour)
        case .friction: return "You were warned on this window. Back to \(task)?"
        case .claim: return "Read as off topic for \(task)."
        }
    }
    public static func shieldAsk(task: String) -> String { "How does this window help with \(task)?" }
    public static let shieldPlaceholder = "I am using this to"
    /// What Hushd says it did after a wrong explanation.
    public static func punishment(_ a: EnforceAction) -> String {
        switch a { case .close: return "Hushd closed the tab."; case .hide: return "Hushd hid the app."; case .switchAway: return "Hushd switched you back." }
    }
    public static func claimsUsedUp(_ n: Int) -> String { "All \(n) explanations used this session." }
    public static func backHoldLine() -> String { "\(Int(Shield.backHoldSeconds)) seconds. Letting go starts over." }
    public static func lockedLine(_ seconds: Int) -> String {
        let m = (seconds + 59) / 60
        return "Not verified. Explaining is locked for \(m) \(m == 1 ? "minute" : "minutes")."
    }

    /// The notch's "still paused?" note: how long it has been, and where to resume. Text only; the notch has no controls.
    public static func heldTitle(seconds: Double) -> String {
        let m = max(1, Int((seconds / 60).rounded()))
        return m >= 60 ? "Paused for \(m / 60) h \(m % 60) min" : "Paused for \(m) min"
    }
    public static let heldMeta = "Resume from the menu bar or Hushd"
    public static func rhythmTitle(_ k: RhythmPrompt.Kind, task: String) -> String {
        switch k {
        case .checkIn: return "Still working on \(task)?"
        case .breakDue(let m): return "Time for a \(m) minute break"
        }
    }
    public static func rhythmBody(_ k: RhythmPrompt.Kind) -> String {
        switch k {
        case .checkIn: return "A quick check-in, whatever is on screen."
        case .breakDue: return "You have worked a full block. Rest your eyes and stand up for a minute."
        }
    }
    /// What the voice says. Short, and the task is the only thing it names.
    public static func spoken(_ e: CueEvent, title: String) -> String? {
        switch e {
        case .headsUp, .friction: return nil
        default: return title
        }
    }
}
