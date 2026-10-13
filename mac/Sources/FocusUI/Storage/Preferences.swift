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
    /// A window whose title or address shares words with the task counts as on task without the model. Quiet by construction.
    public var matchTaskWords: Bool { didSet { defaults.set(matchTaskWords, forKey: "matchTaskWords") } }
    /// Off: the on-device model is never asked. Only project rules, matching words and the never-judged lists decide; everything else
    /// is "not judged" and cannot lead to a nudge.
    public var useModel: Bool { didSet { defaults.set(useModel, forKey: "useModel") } }
    /// Task coach, session recap and Ask Focus, all written by the on-device model. Off: none of them appear.
    public var aiHelp: Bool { didSet { defaults.set(aiHelp, forKey: "aiHelp") } }
    /// Practice mode taken out of the app for good: every session nudges from the start, and no practice screen, count or message appears.
    public var practiceRemoved: Bool { didSet { defaults.set(practiceRemoved, forKey: "practiceRemoved"); if practiceRemoved { practiceSessionsLeft = 0 } } }
    /// Quiet rewards: today's progress toward a daily goal, a streak with rest days, longest stretch, how fast you get back. Off hides all of it.
    public var showProgress: Bool { didSet { defaults.set(showProgress, forKey: "showProgress") } }
    public var dailyGoalMinutes: Int { didSet { defaults.set(dailyGoalMinutes, forKey: "dailyGoalMinutes") } }
    /// Wording of nudges only. Curated lines, never model-written, and none ever names what you were looking at.
    public var nudgeTone: NudgeTone { didSet { defaults.set(nudgeTone.rawValue, forKey: "nudgeTone") } }
    /// One soft system tone when a nudge appears. Off by default (PRODUCT.md: discreet).
    public var nudgeSound: Bool { didSet { defaults.set(nudgeSound, forKey: "nudgeSound") } }
    public static let goalChoices = [30, 60, 90, 120, 180]
    public var practiceActive: Bool { !practiceRemoved && practiceSessionsLeft > 0 }

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
        matchTaskWords = defaults.object(forKey: "matchTaskWords") as? Bool ?? true
        useModel = defaults.object(forKey: "useModel") as? Bool ?? true
        aiHelp = defaults.object(forKey: "aiHelp") as? Bool ?? true
        showProgress = defaults.object(forKey: "showProgress") as? Bool ?? true
        dailyGoalMinutes = defaults.object(forKey: "dailyGoalMinutes") as? Int ?? 90
        nudgeTone = NudgeTone(rawValue: defaults.string(forKey: "nudgeTone") ?? "") ?? .neutral
        nudgeSound = defaults.object(forKey: "nudgeSound") as? Bool ?? false
        let removed = defaults.object(forKey: "practiceRemoved") as? Bool ?? false
        practiceRemoved = removed
        practiceSessionsLeft = removed ? 0 : (defaults.object(forKey: "practiceLeft") as? Int ?? Preferences.practiceSessions)
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
    public func restartPractice() { if !practiceRemoved { practiceSessionsLeft = Preferences.practiceSessions } }
}
