import Foundation

/// Quiet rewards, worked out from saved sessions (seconds only, never text). PRODUCT.md principle 6 sets the limits:
/// nothing is ever taken away, no warning about a streak at risk, no points or levels. A missed day is a rest day, up to two a week.
public enum Rewards {
    /// A "focus day" is a day with at least this much on-task time. A low bar on purpose: starting counts.
    public static let focusDaySeconds = 20.0 * 60
    public static let restDaysPerWeek = 2
    /// Only a stretch this long is worth saying anything about.
    public static let notableStretch = 10.0 * 60

    public enum DayMark: Equatable, Sendable {
        /// A focus day.
        case focus
        /// A missed day the weekly rest allowance covers; the streak carries on.
        case rest
        /// Nothing to show: no session, or before the streak began.
        case none
        /// Today, not a focus day yet. Never a miss, because the day is not over.
        case pending
    }

    public struct Streak: Equatable, Sendable {
        public var current = 0, best = 0
        /// Rest days used inside the last seven days of the current streak.
        public var restUsed = 0
        /// The seven days ending today, oldest first.
        public var week: [(day: Date, mark: DayMark)] = []
        public static func == (a: Streak, b: Streak) -> Bool {
            a.current == b.current && a.best == b.best && a.restUsed == b.restUsed && a.week.map(\.mark) == b.week.map(\.mark)
        }
    }

    static func onTaskByDay(_ sessions: [SessionRecord], _ cal: Calendar) -> [Date: Double] {
        var out: [Date: Double] = [:]
        for s in sessions { out[cal.startOfDay(for: s.start), default: 0] += s.onTaskSeconds }
        return out
    }

    /// Walks the days from the first session to today. A missed day inside the streak is a rest day while no more than `restDays`
    /// of the last seven days are misses; one more and the streak starts over (the best figure stays).
    public static func streak(_ sessions: [SessionRecord], today: Date, calendar cal: Calendar = .current,
                              minimum: Double = focusDaySeconds, restDays: Int = restDaysPerWeek) -> Streak {
        let byDay = onTaskByDay(sessions, cal)
        let todayStart = cal.startOfDay(for: today)
        var out = Streak()
        var marks: [Date: DayMark] = [:]
        func week() -> [(day: Date, mark: DayMark)] {
            (0..<7).reversed().compactMap { back in cal.date(byAdding: .day, value: -back, to: todayStart).map { ($0, marks[$0] ?? DayMark.none) } }
        }
        guard let first = byDay.keys.min(), first <= todayStart else { out.week = week(); return out }
        var window: [Bool] = []          // one flag per day of the current streak; true = missed
        var run = 0
        var day = first
        while day <= todayStart {
            let met = (byDay[day] ?? 0) >= minimum
            if day == todayStart && !met { marks[day] = .pending; break }
            if met {
                run += 1; out.best = max(out.best, run); window.append(false); marks[day] = .focus
            } else if run == 0 {
                marks[day] = .none
            } else {
                window.append(true)
                if window.suffix(7).filter({ $0 }).count <= restDays {
                    marks[day] = .rest
                } else {
                    // The streak ends here. The rest days that were holding it open were just misses.
                    var back = day
                    while let p = cal.date(byAdding: .day, value: -1, to: back), marks[p] == .rest { marks[p] = DayMark.none; back = p }
                    marks[day] = DayMark.none; run = 0; window = []
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        out.current = run
        out.restUsed = run > 0 ? window.suffix(7).filter { $0 }.count : 0
        out.week = week()
        return out
    }

    // MARK: daily goal
    public struct Goal: Equatable, Sendable {
        public var seconds: Double, goalSeconds: Double
        public var fraction: Double { goalSeconds > 0 ? min(1, seconds / goalSeconds) : 0 }
        public var reached: Bool { goalSeconds > 0 && seconds >= goalSeconds }
        public var minutes: Int { Int((seconds / 60).rounded(.down)) }
        public var goalMinutes: Int { Int((goalSeconds / 60).rounded()) }
    }

    public static func goal(_ sessions: [SessionRecord], on day: Date, goalMinutes: Int, calendar cal: Calendar = .current) -> Goal {
        Goal(seconds: DayStats.total(sessions, on: day, calendar: cal).onTaskSeconds, goalSeconds: Double(goalMinutes) * 60)
    }

    // MARK: stretches
    /// Longest run of on-task time without a slip. Not-sure time neither adds to the run nor ends it; being off topic or away does.
    public static func longestStretch(_ segments: [TimelineSegment]) -> Double {
        var best = 0.0, run = 0.0
        for s in segments {
            switch s.kind {
            case .on: run += s.seconds; best = max(best, run)
            case .unsure: break
            case .off, .gap: run = 0
            }
        }
        return best
    }

    /// Practice sessions show every moment as on task (the beacon never leaves "resting"), so they say nothing about stretches or returns.
    static func counts(_ s: SessionRecord) -> Bool { s.practice != true }

    public static func bestStretch(_ sessions: [SessionRecord], on day: Date? = nil, calendar cal: Calendar = .current) -> Double {
        sessions.filter { s in counts(s) && (day.map { cal.isDate(s.start, inSameDayAs: $0) } ?? true) }
            .map { longestStretch($0.segments) }.max() ?? 0
    }

    // MARK: returning
    public struct Returns: Equatable, Sendable { public var average: Double, count: Int }

    public static func returns(_ sessions: [SessionRecord], from: Date, to: Date) -> Returns? {
        let all = sessions.filter { counts($0) && $0.start >= from && $0.start < to }.flatMap { $0.returns ?? [] }
        guard !all.isEmpty else { return nil }
        return Returns(average: all.reduce(0, +) / Double(all.count), count: all.count)
    }

    /// This week's average time to get back on task and last week's, only when each has at least three returns to average.
    public static func returnTrend(_ sessions: [SessionRecord], today: Date, calendar cal: Calendar = .current) -> (thisWeek: Returns, lastWeek: Returns?)? {
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: today))!
        let weekAgo = cal.date(byAdding: .day, value: -7, to: end)!, twoAgo = cal.date(byAdding: .day, value: -14, to: end)!
        guard let now = returns(sessions, from: weekAgo, to: end), now.count >= 3 else { return nil }
        let before = returns(sessions, from: twoAgo, to: weekAgo).flatMap { $0.count >= 3 ? $0 : nil }
        return (now, before)
    }

    // MARK: end-of-session highlight
    public enum Highlight: Equatable, Sendable {
        case longestStretch(minutes: Int)
        case goalReached
        case quickerReturn(seconds: Int, usual: Int)
        case noSlips(minutes: Int)
        case started
        /// A rough session gets kindness, not a score.
        case rough
    }

    /// At most one line about a session that just ended. `others` are the sessions saved before it.
    public static func highlight(for s: SessionRecord, others: [SessionRecord], goalMinutes: Int, showGoal: Bool = true, calendar cal: Calendar = .current) -> Highlight? {
        let onMin = s.onTaskSeconds / 60
        if s.activeSeconds >= 5 * 60, s.offTopicSeconds >= 0.4 * s.activeSeconds { return .rough }
        if counts(s) {
            let mine = longestStretch(s.segments), prior = bestStretch(others)
            if mine >= notableStretch, prior >= notableStretch, mine > prior { return .longestStretch(minutes: Int(mine / 60)) }
        }
        if showGoal, goalMinutes > 0 {
            let before = goal(others, on: s.start, goalMinutes: goalMinutes, calendar: cal)
            let after = goal(others + [s], on: s.start, goalMinutes: goalMinutes, calendar: cal)
            if after.reached && !before.reached { return .goalReached }
        }
        if counts(s), let r = s.returns, r.count >= 2 {
            let mean = r.reduce(0, +) / Double(r.count)
            let from = cal.date(byAdding: .day, value: -14, to: s.start)!
            if let usual = returns(others, from: from, to: s.start), usual.count >= 3, mean <= 0.8 * usual.average {
                return .quickerReturn(seconds: Int(mean.rounded()), usual: Int(usual.average.rounded()))
            }
        }
        if s.drifts == 0 && onMin >= 10 { return .noSlips(minutes: Int(onMin)) }
        return onMin < 10 ? .started : nil
    }

    public static func text(_ h: Highlight) -> String {
        switch h {
        case .longestStretch(let m): return "Your longest stretch yet: \(m) minutes without a slip."
        case .goalReached: return "Daily goal reached."
        case .quickerReturn(let s, let u): return "You got back on task in \(s) seconds on average, quicker than your usual \(u)."
        case .noSlips(let m): return "\(m) minutes with no slips."
        case .started: return "You started. A short session still counts toward your day."
        case .rough: return "That one was rough, and it happens. A shorter session or a break first can help next time."
        }
    }

    public static func duration(_ seconds: Double) -> String {
        let n = Int(seconds.rounded())
        if n < 90 { return "\(n) s" }
        let m = Int((Double(n) / 60).rounded())
        return m < 60 ? "\(m) min" : (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min")
    }
}

/// A short confirmation shown while working: a quick return, the daily goal, a longest stretch. Memory only, gone after a few seconds.
public struct Confirmation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case backOnTrack(seconds: Int)
        case goalReached
        case longestStretch(minutes: Int)
    }
    public var kind: Kind
    public var at: Double

    public var text: String {
        switch kind {
        case .backOnTrack(let s): return s < 90 ? "Back in \(s) s" : "Back after \(Rewards.duration(Double(s)))"
        case .goalReached: return "Daily goal reached"
        case .longestStretch(let m): return "Longest stretch yet: \(m) min"
        }
    }
}
