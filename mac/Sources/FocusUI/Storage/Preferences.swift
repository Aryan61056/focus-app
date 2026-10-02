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
    /// The notch (or floating pill) while a session runs. Aesthetic only; everything it does is also in the app and the menu bar.
    public var showNotch: Bool { didSet { defaults.set(showNotch, forKey: "showNotch") } }
    /// A live picture of the window Focus is reading, shown in the app only. Off until the user asks for it (it needs Screen Recording).
    public var readScreen: Bool { didSet { defaults.set(readScreen, forKey: "readScreen") } }
    /// First-run intro shown once; and the one "too quiet, about right, too loud" question, asked once after the first session that actually nudged.
    public var introSeen: Bool { didSet { defaults.set(introSeen, forKey: "introSeen") } }
    public var loudnessAsked: Bool { didSet { defaults.set(loudnessAsked, forKey: "loudnessAsked") } }
    public var contextTipDismissed: Bool { didSet { defaults.set(contextTipDismissed, forKey: "contextTipDismissed") } }
    public var practiceActive: Bool { practiceSessionsLeft > 0 }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preset = Preset(rawValue: defaults.string(forKey: "preset") ?? "") ?? .gentle
        skipPersonal = defaults.object(forKey: "skipPersonal") as? Bool ?? true
        neverJudgedApps = defaults.stringArray(forKey: "neverJudgedApps") ?? Rules.defaultNeverJudgedApps
        showNotch = defaults.object(forKey: "showNotch") as? Bool ?? true
        readScreen = defaults.object(forKey: "readScreen") as? Bool ?? false
        introSeen = defaults.object(forKey: "introSeen") as? Bool ?? false
        loudnessAsked = defaults.object(forKey: "loudnessAsked") as? Bool ?? false
        contextTipDismissed = defaults.object(forKey: "contextTipDismissed") as? Bool ?? false
        practiceSessionsLeft = defaults.object(forKey: "practiceLeft") as? Int ?? Preferences.practiceSessions
    }

    public enum Loudness: Sendable { case tooQuiet, aboutRight, tooLoud }
    /// One step up or down the presets, never past the ends. Asked once.
    public func answerLoudness(_ a: Loudness) {
        loudnessAsked = true
        switch (a, preset) {
        case (.tooQuiet, .gentle): preset = .standard
        case (.tooQuiet, .standard): preset = .strict
        case (.tooLoud, .strict): preset = .standard
        case (.tooLoud, .standard): preset = .gentle
        default: break
        }
    }

    public func sessionFinished(wasPractice: Bool) { if wasPractice && practiceSessionsLeft > 0 { practiceSessionsLeft -= 1 } }
    public func turnNudgesOnNow() { practiceSessionsLeft = 0 }
    public func restartPractice() { practiceSessionsLeft = Preferences.practiceSessions }
}
