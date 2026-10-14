import Foundation
import FocusUI
import FocusLinkNet

/// What the phone's Insights tab shows, worked out from the Mac's saved sessions with the same functions the Mac's own Insights use,
/// so the two never disagree. Seconds and counts, plus the task names the user typed. No window titles exist in the store to send.
enum InsightsBuilder {
    @MainActor
    static func build(store: DataStore?, prefs: Preferences, todayOnTaskSeconds: Double, now: Date = Date(), calendar cal: Calendar = .current) -> Insights {
        let sessions = store?.sessions ?? []
        let showProgress = prefs.showProgress
        let streak = Rewards.streak(sessions, today: now, calendar: cal)
        let hours = DayStats.week(sessions, endingOn: now, calendar: cal)
        let week: [Insights.Day] = hours.enumerated().map { i, d in
            let mark = i < streak.week.count ? streak.week[i].mark : .none
            return Insights.Day(day: d.day, onTaskSeconds: d.hours * 3600, mark: showProgress ? Self.mark(mark) : .none)
        }
        let trend = Rewards.returnTrend(sessions, today: now, calendar: cal)?.thisWeek
        let recent = sessions.filter { $0.practice != true }.prefix(8).map {
            Insights.Digest(id: $0.id, task: $0.task, start: $0.start, end: $0.end, onTaskSeconds: $0.onTaskSeconds, activeSeconds: $0.activeSeconds, drifts: $0.drifts, practice: false)
        }
        return Insights(
            todayOnTaskSeconds: todayOnTaskSeconds,
            goalMinutes: showProgress ? prefs.dailyGoalMinutes : 0,
            streak: showProgress ? streak.current : 0,
            bestStreak: showProgress ? streak.best : 0,
            restDaysUsed: showProgress ? streak.restUsed : 0,
            week: week,
            recent: Array(recent),
            bestStretchSeconds: showProgress ? Rewards.bestStretch(sessions, on: now, calendar: cal) : 0,
            returnSeconds: showProgress ? trend?.average : nil,
            returnCount: showProgress ? (trend?.count ?? 0) : 0)
    }

    private static func mark(_ m: Rewards.DayMark) -> Insights.Mark {
        switch m { case .focus: .focus; case .rest: .rest; case .none: .none; case .pending: .pending }
    }
}
