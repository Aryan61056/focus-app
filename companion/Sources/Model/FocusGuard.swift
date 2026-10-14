import Foundation
import FocusLinkNet

/// The guard: a Shortcuts automation runs "Guard my session" whenever a social app is opened, and this decides whether that
/// open should bounce you back to Focus. Pure, so it can be tested without a phone, a Mac or Shortcuts.
enum GuardRules {
    /// With the Mac out of reach, a note from earlier than this is not trusted: a sleeping Mac must not pin the phone for hours.
    static let staleAfter: TimeInterval = 20 * 60
    /// How long the check waits for the Mac to answer before it falls back to its last note. Shortcuts runs it while an app opens.
    static let patience: TimeInterval = 2

    /// Working, in the sense that matters here: a pause, a break and a practice session leave every app open.
    static func isWorking(_ s: SessionState) -> Bool {
        guard !s.practice else { return false }
        switch s.phase {
        case .onTask, .unsure, .drifting, .recovering: return true
        case .idle, .paused, .onBreak: return false
        }
    }

    /// `live` means the Mac answered just now, so the clock can be trusted whatever its age.
    static func shouldBounce(_ clock: SessionClock, live: Bool, now: Date) -> Bool {
        guard isWorking(clock.state) else { return false }
        if live { return true }
        if now.timeIntervalSince(clock.receivedAt) > staleAfter { return false }
        if clock.state.timed, clock.seconds(at: now) <= 0 { return false }
        return true
    }
}

/// The last thing the Mac said, kept so the check still has an answer when the phone was asleep and the Mac cannot be reached.
struct GuardCache {
    private struct Note: Codable { var state: SessionState; var receivedAt: Date }
    var defaults: UserDefaults = .standard
    private let key = "guard.note"

    func save(_ clock: SessionClock) {
        if let data = try? JSONEncoder().encode(Note(state: clock.state, receivedAt: clock.receivedAt)) { defaults.set(data, forKey: key) }
    }
    func load() -> SessionClock? {
        guard let data = defaults.data(forKey: key), let n = try? JSONDecoder().decode(Note.self, from: data) else { return nil }
        return SessionClock(state: n.state, receivedAt: n.receivedAt)
    }
    func clear() { defaults.removeObject(forKey: key) }
}

/// Apps people most often want out of the way. Only used to show what to pick in Shortcuts: iOS gives Focus no list of
/// installed apps, and Shortcuts is where the person actually chooses.
enum SocialApps {
    static let suggestions = ["Instagram", "TikTok", "YouTube", "Snapchat", "X", "Reddit", "Facebook", "Threads", "Discord", "Pinterest"]
}

/// What the last run of the guard decided, kept so the Block tab can say whether the automation is firing at all.
enum GuardOutcome: String, Codable {
    case sentBack, noSession, switchedOff, demo, notPaired

    var bounces: Bool { self == .sentBack }
    var sentence: String {
        switch self {
        case .sentBack: String(localized: "sent you back to your session")
        case .noSession: String(localized: "no session was running, so the app opened as normal")
        case .switchedOff: String(localized: "the guard was switched off, so the app opened as normal")
        case .demo: String(localized: "demo mode never guards")
        case .notPaired: String(localized: "no Mac is paired yet")
        }
    }
}

struct GuardLog {
    private struct Entry: Codable { var at: Date; var outcome: GuardOutcome }
    var defaults: UserDefaults = .standard
    private let key = "guard.last"
    func record(_ outcome: GuardOutcome, at: Date = .now) {
        if let data = try? JSONEncoder().encode(Entry(at: at, outcome: outcome)) { defaults.set(data, forKey: key) }
    }
    func last() -> (at: Date, outcome: GuardOutcome)? {
        guard let data = defaults.data(forKey: key), let e = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        return (e.at, e.outcome)
    }
}
