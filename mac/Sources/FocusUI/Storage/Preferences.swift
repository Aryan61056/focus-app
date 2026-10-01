import Foundation
import Observation
import FocusBrain
import FocusJudge

/// Settings that live in UserDefaults. Practice mode (shadow) is on for the first three sessions, then the owner-chosen
/// preset takes over; the count is a product choice still open (docs/BRAIN-SPEC.md question 4).
@MainActor @Observable
public final class Preferences {
    public static let practiceSessions = 3
    @ObservationIgnored private let defaults: UserDefaults
    public var preset: Preset { didSet { defaults.set(preset.rawValue, forKey: "preset") } }
    public var practiceSessionsLeft: Int { didSet { defaults.set(practiceSessionsLeft, forKey: "practiceLeft") } }
    /// Personal messaging, music and blank pages are not judged. The list is editable; the switch turns the whole idea off.
    public var skipPersonal: Bool { didSet { defaults.set(skipPersonal, forKey: "skipPersonal") } }
    public var neverJudgedApps: [String] { didSet { defaults.set(neverJudgedApps, forKey: "neverJudgedApps") } }
    public var practiceActive: Bool { practiceSessionsLeft > 0 }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preset = Preset(rawValue: defaults.string(forKey: "preset") ?? "") ?? .gentle
        skipPersonal = defaults.object(forKey: "skipPersonal") as? Bool ?? true
        neverJudgedApps = defaults.stringArray(forKey: "neverJudgedApps") ?? Rules.defaultNeverJudgedApps
        practiceSessionsLeft = defaults.object(forKey: "practiceLeft") as? Int ?? Preferences.practiceSessions
    }

    public func sessionFinished(wasPractice: Bool) { if wasPractice && practiceSessionsLeft > 0 { practiceSessionsLeft -= 1 } }
    public func turnNudgesOnNow() { practiceSessionsLeft = 0 }
    public func restartPractice() { practiceSessionsLeft = Preferences.practiceSessions }
}
