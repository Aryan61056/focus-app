import Foundation

/// How a nudge sounds. Curated lines only (PLAN C13): the same facts in three registers, none of them naming the distraction.
public enum NudgeTone: String, CaseIterable, Identifiable, Sendable {
    case neutral, coach, direct
    public var id: String { rawValue }
    public var title: String { switch self { case .neutral: return "Neutral"; case .coach: return "Coach"; case .direct: return "Direct" } }
    public var example: String {
        switch self { case .neutral: return "Back to your task?"; case .coach: return "Ready to pick it back up?"; case .direct: return "Back to your task." }
    }
}

/// Every word a nudge shows, in one place so tone, repeat and the long-detour check are testable.
/// Rules (PLAN 4.12): second person, sentence case, no exclamation marks, never the name of what you were looking at.
public enum NudgeCopy {
    /// A detour this long (seconds off topic in one block) gets an offer of a break instead of another push.
    public static let longDetour = 8.0 * 60
    public static let breakMinutes = 5

    /// `kind` is the surface kind ("notice", "card"); `severity` is 1 for the first nudge in a block and 2 after.
    public static func title(kind: String, severity: Int, tone: NudgeTone, task: String, longDetour: Bool) -> String {
        if longDetour {
            switch tone {
            case .neutral: return "That has been a long detour. Take a short break first?"
            case .coach: return "Long detours happen. A short break can reset things."
            case .direct: return "Away a long time. Take a break, then restart."
            }
        }
        let repeated = severity >= 2
        switch (tone, kind == "notice") {
        case (.neutral, true): return "Still on \(task)?"
        case (.neutral, false): return repeated ? "Ready to go back to \(task)?" : "Back to \(task)?"
        case (.coach, true): return "How is \(task) going?"
        case (.coach, false): return repeated ? "\(task) is here whenever you are." : "Ready to pick \(task) back up?"
        case (.direct, true): return "Is this \(task)?"
        case (.direct, false): return repeated ? "Back to \(task). You have been away a while." : "Back to \(task)."
        }
    }

    public static func gateBody(tone: NudgeTone, task: String, longDetour: Bool) -> String {
        if longDetour { return "A break might help more than another push." }
        switch tone {
        case .neutral: return "You have been away from \(task) for a while."
        case .coach: return "Whenever you are ready, \(task) is waiting."
        case .direct: return "Back to \(task)."
        }
    }

    public static func breakButton() -> String { "Take a \(breakMinutes) minute break" }
    public static func shortBreakButton() -> String { "Take a break" }
}
