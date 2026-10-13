import Foundation

// Everything around the warning that is not the warning itself: the heads-up before it, the small banner over the window you drifted into,
// the cues outside the app (menu bar, Dock, trackpad, voice), the friction before going back, the scheduled rhythm, and how hard Focus
// pushes at different times of day. All of it lives in the controller layer, so the brain and its golden traces are unchanged.
// Pure types and rules here; SessionController+Cues.swift wires them to the session.

// MARK: heads-up before a warning

/// Watches the last few readings for the shape of a rabbit hole, before the brain has confirmed a drift.
/// Two shapes count: several off-topic readings in a row, or hopping between windows that are all off or not sure.
/// Owner, 2026-10-13: wants Focus to speak up earlier. The cost is more mistaken heads-ups, so it is only a banner (no sound), it waits
/// five minutes between heads-ups, and "It's part of it" teaches Focus the window.
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

/// The small banner over the window you are in. `early` is the heads-up; `reminder` stays from the warning until you are back.
public struct Banner: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case early, reminder }
    public var kind: Kind
    public var at: Double
}

// MARK: cues outside the app

/// Things worth a cue. The controller decides which channels each one uses from the user's switches.
public enum CueEvent: Equatable, Sendable {
    case headsUp, warning, checkIn, pauseScreen, enforce, friction, rhythmCheckIn, breakDue
    /// The loud ones: a nudge you ignored, or something that needs an answer. The heads-up stays light.
    var firm: Bool { self != .headsUp }
    /// The Dock bounce is for what happens while you are in another app.
    var bouncesDock: Bool { self != .headsUp }
    var speaks: Bool { self != .headsUp && self != .friction }
}

public enum HapticPattern: Equatable, Sendable {
    /// One light tap.
    case light
    /// Two firmer taps a moment apart.
    case firm
    /// Seconds between taps of a pattern, so a player can schedule them.
    public var taps: [Double] { switch self { case .light: return [0]; case .firm: return [0, 0.14] } }
}

/// How the menu bar icon reads: plain, a soft tint for a heads-up or a prompt, or the warm tint and a slow pulse while you are away.
public enum MenuCue: Equatable, Sendable { case none, headsUp, away }

// MARK: friction before going back

/// After a pause screen, the same site asks for a moment before it opens again. Either hold for a few seconds, or say why it belongs.
public struct Friction: Equatable, Sendable {
    public var app: String
    public var siteKey: String
    public var at: Double
    /// How long the hold takes. A reason needs at least this many characters (about a short sentence).
    public static let holdSeconds = 5.0
    public static let passSeconds = 600.0
    public static let minimumReason = 12
    public static func acceptable(reason: String) -> Bool {
        let t = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count >= minimumReason && t.split(whereSeparator: { $0.isWhitespace }).count >= 2
    }
}

// MARK: scheduled rhythm

public enum Rhythm: String, CaseIterable, Identifiable, Sendable {
    case off, checkIns, pomodoro
    public var id: String { rawValue }
    public var title: String { switch self { case .off: return "Off"; case .checkIns: return "Check-ins"; case .pomodoro: return "Work and break" } }
    public var detail: String {
        switch self {
        case .off: return "Focus only speaks up when you drift."
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
    public enum Kind: Equatable, Sendable { case checkIn, breakDue(minutes: Int) }
    public var kind: Kind
    public var at: Double
}

// MARK: pressure through the day

/// How hard Focus pushes. Easy in the morning, steady when you are on pace for your daily goal, firmer when you are behind it.
/// It changes how quickly Focus warns and climbs, never what counts as off task, and the app always says which level it is at and why.
public enum DayPressure: Int, Comparable, Sendable {
    case relaxed, steady, behind, wellBehind
    public static func < (a: DayPressure, b: DayPressure) -> Bool { a.rawValue < b.rawValue }

    /// Multiplies the time Focus waits (smaller is quicker). Applied to the brain's check scale when a session begins, and to the ladder live.
    public var factor: Double { switch self { case .relaxed: return 1.25; case .steady: return 1.0; case .behind: return 0.8; case .wellBehind: return 0.65 } }
    /// Extra seconds the pause screen holds the easy exits.
    public var extraHold: Double { switch self { case .relaxed, .steady: return 0; case .behind: return 5; case .wellBehind: return 10 } }

    /// The working day the pace is measured over. Before `morningUntil` Focus is easy whatever you have done.
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

/// A line for Today that says why Focus is pushing the way it is. Honest and plain: it never hides a change in how firm Focus is.
public enum PaceCopy {
    public static func line(_ p: DayPressure, goalReached: Bool, behindMinutes: Int) -> String? {
        switch p {
        case .steady: return nil
        case .relaxed: return goalReached ? "You reached today's goal, so Focus is easy on you now." : "It is early in the day, so Focus is easy on you."
        case .behind: return "You are a little behind today's goal, so Focus speaks up sooner."
        case .wellBehind: return behindMinutes > 0 ? "You are about \(behindMinutes) minutes behind today's goal, so Focus is firmer." : "You are well behind today's goal, so Focus is firmer."
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
    public static func bannerTitle(_ kind: Banner.Kind, tone: NudgeTone, task: String) -> String {
        switch (kind, tone) {
        case (.early, .neutral): return "Still on \(task)?"
        case (.early, .coach): return "Easing away from \(task)?"
        case (.early, .direct): return "Drifting from \(task)?"
        case (.reminder, .neutral): return "Your task: \(task)"
        case (.reminder, .coach): return "\(task) is waiting for you"
        case (.reminder, .direct): return "Back to \(task)"
        }
    }

    public static func frictionTitle(task: String) -> String { "This is where you drifted" }
    public static func frictionBody(task: String) -> String { "Hold for a few seconds to open it anyway, or say how it helps with \(task)." }

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
