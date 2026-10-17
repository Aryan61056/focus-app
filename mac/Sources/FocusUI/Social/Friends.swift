import Foundation

// Friends (docs/SOCIAL.md). Only numbers ever leave the Mac: focused seconds, slips and sessions per day, and a streak.
// No task, project, app, site, window or screen text is in any type here, so none of it can be shared by mistake.

/// One day of someone's focus, as a friend sees it.
public struct ShareDay: Codable, Equatable, Sendable {
    /// The local calendar day, "yyyy-MM-dd", so a friend in another time zone still lines days up the way you lived them.
    public var day: String
    public var focusedSeconds: Double
    public var slips: Int
    public var sessions: Int
    public init(day: String, focusedSeconds: Double, slips: Int, sessions: Int) {
        self.day = day; self.focusedSeconds = focusedSeconds; self.slips = slips; self.sessions = sessions
    }
}

/// What one person shares: a name they chose and their last two weeks of numbers.
public struct FriendCard: Codable, Equatable, Identifiable, Sendable {
    /// The transport's id for this person (their iCloud user record name). Never shown.
    public var id: String
    public var name: String
    public var days: [ShareDay]
    public var streak: Int
    public var updated: Date
    /// An avatar picked from `avatars`; nil shows the name's first letter. Anything not on the list is dropped when a card arrives.
    public var emoji: String?
    public init(id: String, name: String, days: [ShareDay], streak: Int, updated: Date, emoji: String? = nil) {
        self.id = id; self.name = name; self.days = days; self.streak = streak; self.updated = updated
        self.emoji = emoji.flatMap { FriendCard.avatars.contains($0) ? $0 : nil }
    }

    /// The avatars on offer. A fixed list, like cheers, so nothing typed travels.
    public static let avatars = ["\u{1F98A}", "\u{1F43C}", "\u{1F438}", "\u{1F989}", "\u{1F419}", "\u{1F41D}",
                                 "\u{1F335}", "\u{1F340}", "\u{1F680}", "\u{2B50}", "\u{1F3A7}", "\u{1F4DA}"]

    /// Days kept on a card: this week and last, whatever day the week starts on.
    public static let daysKept = 14

    static func key(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Your card, made from saved sessions. Practice sessions are left out: they do not classify, so their minutes say nothing.
    public static func mine(id: String, name: String, emoji: String? = nil, sessions: [SessionRecord], today: Date, calendar cal: Calendar = .current) -> FriendCard {
        let counted = sessions.filter { $0.practice != true }
        let start = cal.startOfDay(for: today)
        var days: [ShareDay] = []
        for back in (0..<daysKept).reversed() {
            guard let d = cal.date(byAdding: .day, value: -back, to: start) else { continue }
            let s = counted.filter { cal.isDate($0.start, inSameDayAs: d) }
            guard !s.isEmpty else { continue }
            days.append(ShareDay(day: key(d, cal), focusedSeconds: s.reduce(0) { $0 + $1.onTaskSeconds }.rounded(),
                                 slips: s.reduce(0) { $0 + $1.drifts }, sessions: s.count))
        }
        return FriendCard(id: id, name: name, days: days, streak: Rewards.streak(counted, today: today, calendar: cal).current, updated: today, emoji: emoji)
    }
}

/// A reply to a friend: an emoji or a line from a fixed list. Nothing typed, so no free text is ever sent.
public enum CheerKind: String, Codable, CaseIterable, Sendable {
    case fire, clap, strong, sprout, coffee
    case niceWork, keepGoing, freshStart, withYou, proud

    public static let emoji: [CheerKind] = [.fire, .clap, .strong, .sprout, .coffee]
    public static let lines: [CheerKind] = [.niceWork, .keepGoing, .freshStart, .withYou, .proud]

    public var text: String {
        switch self {
        case .fire: return "\u{1F525}"; case .clap: return "\u{1F44F}"; case .strong: return "\u{1F4AA}"
        case .sprout: return "\u{1F331}"; case .coffee: return "\u{2615}\u{FE0F}"
        case .niceWork: return "Nice work today"
        case .keepGoing: return "Keep going"
        case .freshStart: return "Tomorrow is a fresh start"
        case .withYou: return "Focusing with you"
        case .proud: return "Proud of you"
        }
    }
    public var isEmoji: Bool { CheerKind.emoji.contains(self) }
    /// What VoiceOver says for an emoji, which it would otherwise read as its Unicode name.
    public var spoken: String {
        switch self {
        case .fire: return "On fire"; case .clap: return "Applause"; case .strong: return "Strong"
        case .sprout: return "Growing"; case .coffee: return "Coffee"
        default: return text
        }
    }
}

public struct Cheer: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// The sender's id; the transport takes it from who wrote the record, never from a field the sender filled in.
    public var from: String
    public var kind: CheerKind
    public var at: Date
    public init(id: String, from: String, kind: CheerKind, at: Date) { self.id = id; self.from = from; self.kind = kind; self.at = at }
}

/// Pure scoreboard maths, apart from the views so it can be tested. Resets each calendar week.
public enum Scoreboard {
    public enum Board: String, CaseIterable, Identifiable, Sendable {
        case focused = "Most focused", steady = "Fewest slips"
        public var id: String { rawValue }
    }
    /// The Fewest slips board ranks only people with this much focus in the week, so not using Focus never wins it.
    public static let steadyMinimum = 3600.0

    public struct Entry: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var emoji: String?
        public var isYou: Bool
        public var focusedSeconds: Double
        public var slips: Int
        public var sessions: Int
        public var streak: Int
        /// Focused seconds for each day of the week, first day of the week first.
        public var week: [Double]
        public var slipsByDay: [Int]
        /// nil: not ranked on this board (Fewest slips needs an hour of focus).
        public var rank: Int?
        public var slipsPerHour: Double? { focusedSeconds >= Scoreboard.steadyMinimum ? Double(slips) / (focusedSeconds / 3600) : nil }
    }

    /// The days of the calendar week holding `today`, as card keys.
    public static func weekKeys(_ today: Date, calendar cal: Calendar = .current) -> [String] {
        guard let start = cal.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }.map { FriendCard.key($0, cal) }
    }

    public static func entries(_ cards: [FriendCard], you: String?, board: Board, today: Date, calendar cal: Calendar = .current) -> [Entry] {
        let keys = weekKeys(today, calendar: cal)
        var out = cards.map { c -> Entry in
            let byDay = Dictionary(c.days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
            let week = keys.map { byDay[$0] }
            return Entry(id: c.id, name: c.name, emoji: c.emoji, isYou: c.id == you,
                         focusedSeconds: week.reduce(0) { $0 + ($1?.focusedSeconds ?? 0) },
                         slips: week.reduce(0) { $0 + ($1?.slips ?? 0) }, sessions: week.reduce(0) { $0 + ($1?.sessions ?? 0) },
                         streak: c.streak, week: week.map { $0?.focusedSeconds ?? 0 }, slipsByDay: week.map { $0?.slips ?? 0 }, rank: nil)
        }
        // Ties share a rank; ties are then listed by name so the order never jumps between refreshes.
        switch board {
        case .focused:
            out.sort { ($0.focusedSeconds, $1.name) > ($1.focusedSeconds, $0.name) }
            rank(&out) { $0.focusedSeconds }
        case .steady:
            out.sort { a, b in
                switch (a.slipsPerHour, b.slipsPerHour) {
                case let (x?, y?): return x != y ? x < y : (a.focusedSeconds != b.focusedSeconds ? a.focusedSeconds > b.focusedSeconds : a.name < b.name)
                case (.some, nil): return true
                case (nil, .some): return false
                default: return a.focusedSeconds != b.focusedSeconds ? a.focusedSeconds > b.focusedSeconds : a.name < b.name
                }
            }
            rank(&out) { $0.slipsPerHour.map { -$0 } }
        }
        return out
    }

    /// Standard competition ranking (1, 1, 3) on a key where higher is better; a nil key is unranked.
    static func rank(_ e: inout [Entry], by key: (Entry) -> Double?) {
        var last: Double?; var lastRank = 0
        for i in e.indices {
            guard let k = key(e[i]) else { e[i].rank = nil; continue }
            if let last, abs(last - k) < 1e-9 { e[i].rank = lastRank } else { lastRank = i + 1; e[i].rank = lastRank }
            last = k
        }
    }
}
