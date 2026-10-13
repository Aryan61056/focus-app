import Foundation
import FocusBrain

/// What happens when you are warned and stay away. The warning itself (a note or a card) is the brain's; everything after it is this ladder,
/// which keeps climbing while the brain still says "interrupted". Dismissing a card does not stop it; being back on task does.
/// Owner, 2026-10-13: "if the user doesn't get back on task after getting warned ... proactively check ... more punishments ... much more proactive".
public enum EscalationStep: Int, Comparable, Sendable {
    /// The warning only.
    case warned = 0
    /// Focus asks "Are you working on <task>?" and reads the window again.
    case checkIn
    /// The pause screen, with the easy way out held back for a few seconds.
    case pauseScreen
    /// The app you drifted into is hidden and the task comes forward, then again every `enforceEvery` seconds.
    case enforce
    public static func < (a: EscalationStep, b: EscalationStep) -> Bool { a.rawValue < b.rawValue }
}

public struct EscalationPlan: Equatable, Sendable {
    /// Seconds after the warning at which each step begins.
    public var checkInAfter: Double, pauseAfter: Double, enforceAfter: Double
    public var enforceEvery: Double
    /// Seconds the "That was fine" and "Snooze" buttons stay disabled on the pause screen.
    public var holdSeconds: Double

    public static let standard = EscalationPlan(checkInAfter: 40, pauseAfter: 100, enforceAfter: 200, enforceEvery: 120, holdSeconds: 10)
    public static let strict = EscalationPlan(checkInAfter: 20, pauseAfter: 45, enforceAfter: 120, enforceEvery: 60, holdSeconds: 15)

    /// Gentle has no ladder: it is the preset for people who want a single quiet note.
    public static func of(_ p: Preset) -> EscalationPlan? {
        switch p { case .gentle: return nil; case .standard: return .standard; case .strict: return .strict }
    }

    public func step(after seconds: Double) -> EscalationStep {
        if seconds >= enforceAfter { return .enforce }
        if seconds >= pauseAfter { return .pauseScreen }
        if seconds >= checkInAfter { return .checkIn }
        return .warned
    }

    /// Which enforcement round (1, 2, ...) is due at this many seconds, so each fires once.
    public func enforceRound(after seconds: Double) -> Int {
        seconds < enforceAfter ? 0 : 1 + Int((seconds - enforceAfter) / max(1, enforceEvery))
    }

    /// The least gray the screen may be (percent) at this step, whatever the brain's own veil says.
    public static func veilFloor(_ s: EscalationStep) -> Int {
        switch s { case .warned: return 0; case .checkIn: return 70; case .pauseScreen: return 90; case .enforce: return 100 }
    }
}

/// Apps that are never hidden as a consequence: Focus itself and the system's own surfaces.
public enum Enforcement {
    static let protected: Set<String> = ["focus", "finder", "system settings", "loginwindow", "dock", "control center"]
    public static func canHide(_ app: String?) -> Bool {
        guard let a = app?.trimmingCharacters(in: .whitespaces).lowercased(), !a.isEmpty else { return false }
        return !protected.contains(a)
    }
}
