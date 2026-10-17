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
    /// The welcome window (what Focus does, window access, the first task) was finished or skipped.
    public var welcomeSeen: Bool { didSet { defaults.set(welcomeSeen, forKey: "welcomeSeen") } }
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
    /// Friends (docs/SOCIAL.md): your daily numbers go to the friends you invite through iCloud. Off by default; turning it off deletes them.
    public var shareWithFriends: Bool { didSet { defaults.set(shareWithFriends, forKey: "shareWithFriends") } }
    /// The name friends see. Empty until you type one.
    public var friendName: String { didSet { defaults.set(friendName, forKey: "friendName") } }
    /// The avatar friends see, from FriendCard.avatars. Empty shows your first letter.
    public var friendEmoji: String { didSet { defaults.set(friendEmoji, forKey: "friendEmoji") } }
    /// The Friends board last looked at, so the page opens where you left it.
    public var friendsBoard: String { didSet { defaults.set(friendsBoard, forKey: "friendsBoard") } }
    public var dailyGoalMinutes: Int { didSet { defaults.set(dailyGoalMinutes, forKey: "dailyGoalMinutes") } }
    /// Wording of nudges only. Curated lines, never model-written, and none ever names what you were looking at.
    public var nudgeTone: NudgeTone { didSet { defaults.set(nudgeTone.rawValue, forKey: "nudgeTone") } }
    /// One soft system tone when a nudge appears. Off by default (PRODUCT.md: discreet).
    public var nudgeSound: Bool { didSet { defaults.set(nudgeSound, forKey: "nudgeSound") } }
    /// How often Focus looks at the window and how soon it warns. Often is the default; Normal is the spec's original timing.
    public var checkRate: CheckRate { didSet { defaults.set(checkRate.rawValue, forKey: "checkRate") } }
    /// How sure the on-device model must be before a window counts as off task.
    public var sensitivity: Sensitivity { didSet { defaults.set(sensitivity.rawValue, forKey: "sensitivity") } }
    /// If you stay away after a warning: a check-in, a pause screen, then the app you drifted into is hidden (see Escalation.swift). Off: the warning only.
    public var escalate: Bool { didSet { defaults.set(escalate, forKey: "escalate") } }
    /// The whole screen, every display, fades toward gray while you are off task (not only Focus's own window).
    public var screenGrayscale: Bool { didSet { defaults.set(screenGrayscale, forKey: "screenGrayscale") } }
    /// The last step of the ladder. Hiding an app is reversible (click it in the Dock) and never closes it or loses its work.
    public var hideDistractingApp: Bool { didSet { defaults.set(hideDistractingApp, forKey: "hideDistractingApp") } }
    /// The first time the ladder acts on a browser, it switches to the tab you were last working in instead of only hiding the app.
    public var switchTabs: Bool { didSet { defaults.set(switchTabs, forKey: "switchTabs") } }
    /// On Strict, the later rounds close the browser tab you were warned about. Never other apps, never private or never-judged windows.
    public var closeOnStrict: Bool { didSet { defaults.set(closeOnStrict, forKey: "closeOnStrict") } }
    /// Offer to restart into a newer build found on this Mac. Local only; it never installs anything by itself.
    public var offerUpdates: Bool { didSet { defaults.set(offerUpdates, forKey: "offerUpdates") } }
    // MARK: cues around the warning (see Cues.swift)
    /// A small banner with your task over the window you are in: a heads-up before a warning, then a reminder from the warning until you are back. Never any sound.
    public var showBanner: Bool { didSet { defaults.set(showBanner, forKey: "showBanner") } }
    /// The heads-up before a warning, when your recent windows look like a rabbit hole. Needs the banner.
    public var headsUp: Bool { didSet { defaults.set(headsUp, forKey: "headsUp") } }
    /// The menu bar ring takes a soft tint for a heads-up and a warm tint with a slow pulse while you are away.
    public var menuBarCue: Bool { didSet { defaults.set(menuBarCue, forKey: "menuBarCue") } }
    /// The Dock icon bounces once for a warning, a climb step or a prompt while Focus is in the background.
    public var dockBounce: Bool { didSet { defaults.set(dockBounce, forKey: "dockBounce") } }
    /// A tap on the trackpad with a warning. Silent and private; it only works on a Force Touch trackpad with a finger resting on it.
    public var hapticTap: Bool { didSet { defaults.set(hapticTap, forKey: "hapticTap") } }
    /// The Mac's own voice says the nudge aloud. Off by default because it is the one cue other people in the room can hear.
    public var speakNudges: Bool { didSet { defaults.set(speakNudges, forKey: "speakNudges") } }
    /// After a pause screen, opening the same site again asks for a short hold or a typed reason.
    public var frictionReturn: Bool { didSet { defaults.set(frictionReturn, forKey: "frictionReturn") } }
    /// On the pause, cover and claim screens, "Back to task" asks for a short press and hold, as a way to commit to going back. Off by default.
    public var holdToReturn: Bool { didSet { defaults.set(holdToReturn, forKey: "holdToReturn") } }
    /// Scheduled prompts: a check-in at an interval, or a work-and-break rhythm.
    public var rhythm: Rhythm { didSet { defaults.set(rhythm.rawValue, forKey: "rhythm") } }
    public var checkInMinutes: Int { didSet { defaults.set(checkInMinutes, forKey: "checkInMinutes") } }
    /// Easy in the morning, firmer when you are behind the day's goal (DayPressure).
    public var paceMatters: Bool { didSet { defaults.set(paceMatters, forKey: "paceMatters") } }
    public static let goalChoices = [30, 60, 90, 120, 180]
    /// How large the app window's text is drawn, 1 to 1.5 (General, Text size). The notch and the over-window banner keep their size.
    public var textScale: Double { didSet { defaults.set(textScale, forKey: "textScale"); TextScale.shared.factor = CGFloat(textScale) } }
    public var practiceActive: Bool { !practiceRemoved && practiceSessionsLeft > 0 }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preset = Preset(rawValue: defaults.string(forKey: "preset") ?? "") ?? .standard
        skipPersonal = defaults.object(forKey: "skipPersonal") as? Bool ?? true
        neverJudgedApps = defaults.stringArray(forKey: "neverJudgedApps") ?? Rules.defaultNeverJudgedApps
        showNotch = defaults.object(forKey: "showNotch") as? Bool ?? true
        readScreen = defaults.object(forKey: "readScreen") as? Bool ?? false
        introSeen = defaults.object(forKey: "introSeen") as? Bool ?? false
        welcomeSeen = defaults.object(forKey: "welcomeSeen") as? Bool ?? false
        loudnessAsked = defaults.object(forKey: "loudnessAsked") as? Bool ?? false
        contextTipDismissed = defaults.object(forKey: "contextTipDismissed") as? Bool ?? false
        matchTaskWords = defaults.object(forKey: "matchTaskWords") as? Bool ?? true
        useModel = defaults.object(forKey: "useModel") as? Bool ?? true
        aiHelp = defaults.object(forKey: "aiHelp") as? Bool ?? true
        showProgress = defaults.object(forKey: "showProgress") as? Bool ?? true
        shareWithFriends = defaults.bool(forKey: "shareWithFriends")
        friendName = defaults.string(forKey: "friendName") ?? ""
        friendEmoji = defaults.string(forKey: "friendEmoji") ?? ""
        friendsBoard = defaults.string(forKey: "friendsBoard") ?? ""
        dailyGoalMinutes = defaults.object(forKey: "dailyGoalMinutes") as? Int ?? 90
        nudgeTone = NudgeTone(rawValue: defaults.string(forKey: "nudgeTone") ?? "") ?? .neutral
        checkRate = CheckRate(rawValue: defaults.string(forKey: "checkRate") ?? "") ?? .often
        sensitivity = Sensitivity(rawValue: defaults.string(forKey: "sensitivity") ?? "") ?? .proactive
        escalate = defaults.object(forKey: "escalate") as? Bool ?? true
        screenGrayscale = defaults.object(forKey: "screenGrayscale") as? Bool ?? true
        hideDistractingApp = defaults.object(forKey: "hideDistractingApp") as? Bool ?? true
        offerUpdates = defaults.object(forKey: "offerUpdates") as? Bool ?? true
        switchTabs = defaults.object(forKey: "switchTabs") as? Bool ?? true
        closeOnStrict = defaults.object(forKey: "closeOnStrict") as? Bool ?? true
        showBanner = defaults.object(forKey: "showBanner") as? Bool ?? true
        headsUp = defaults.object(forKey: "headsUp") as? Bool ?? true
        menuBarCue = defaults.object(forKey: "menuBarCue") as? Bool ?? true
        dockBounce = defaults.object(forKey: "dockBounce") as? Bool ?? true
        hapticTap = defaults.object(forKey: "hapticTap") as? Bool ?? true
        speakNudges = defaults.object(forKey: "speakNudges") as? Bool ?? false
        frictionReturn = defaults.object(forKey: "frictionReturn") as? Bool ?? true
        holdToReturn = defaults.object(forKey: "holdToReturn") as? Bool ?? false
        rhythm = Rhythm(rawValue: defaults.string(forKey: "rhythm") ?? "") ?? .off
        checkInMinutes = defaults.object(forKey: "checkInMinutes") as? Int ?? 25
        paceMatters = defaults.object(forKey: "paceMatters") as? Bool ?? true
        nudgeSound = defaults.object(forKey: "nudgeSound") as? Bool ?? false
        let scale = min(1.5, max(1, defaults.object(forKey: "textScale") as? Double ?? 1))
        textScale = scale
        TextScale.shared.factor = CGFloat(scale)
        let removed = defaults.object(forKey: "practiceRemoved") as? Bool ?? true
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

/// How often Focus looks. The scale multiplies the brain's check intervals and its grace and confirm delays (SessionConfig.checkScale).
public enum CheckRate: String, CaseIterable, Identifiable, Sendable {
    case rarely, normal, often, veryOften
    public var id: String { rawValue }
    public var scale: Double { switch self { case .rarely: return 1.6; case .normal: return 1.0; case .often: return 0.6; case .veryOften: return 0.4 } }
    public var title: String { switch self { case .rarely: return "Less often"; case .normal: return "Normal"; case .often: return "Often"; case .veryOften: return "Very often" } }
    public var detail: String {
        switch self {
        case .rarely: return "Looks about every 50 to 150 seconds on task, warns later."
        case .normal: return "The original timing: every 30 to 90 seconds on task."
        case .often: return "About every 18 to 54 seconds on task, every 6 when something looks off. Warns sooner."
        case .veryOften: return "About every 12 to 36 seconds on task, every 4 when something looks off. Warns soonest."
        }
    }
}
