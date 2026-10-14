import Foundation

/// The numbers behind the phone's Insights tab. Seconds and counts only, like everything the Mac saves.
public struct Insights: Codable, Equatable, Sendable {
    public enum Mark: String, Codable, Sendable { case focus, rest, none, pending }

    public struct Day: Codable, Equatable, Sendable, Identifiable {
        public var day: Date
        public var onTaskSeconds: Double
        public var mark: Mark
        public var id: Date { day }
        public init(day: Date, onTaskSeconds: Double, mark: Mark) { self.day = day; self.onTaskSeconds = onTaskSeconds; self.mark = mark }
    }

    public struct Digest: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var task: String
        public var start: Date
        public var end: Date
        public var onTaskSeconds: Double
        public var activeSeconds: Double
        public var drifts: Int
        public var practice: Bool
        public init(id: UUID, task: String, start: Date, end: Date, onTaskSeconds: Double, activeSeconds: Double, drifts: Int, practice: Bool) {
            self.id = id; self.task = task; self.start = start; self.end = end; self.onTaskSeconds = onTaskSeconds
            self.activeSeconds = activeSeconds; self.drifts = drifts; self.practice = practice
        }
    }

    public var todayOnTaskSeconds: Double
    /// Zero means the goal is switched off on the Mac.
    public var goalMinutes: Int
    public var streak: Int
    public var bestStreak: Int
    public var restDaysUsed: Int
    /// The seven days ending today, oldest first.
    public var week: [Day]
    /// The last few sessions, newest first.
    public var recent: [Digest]
    public var bestStretchSeconds: Double
    /// Average seconds to get back on task after a flagged drift, this week. Nil with no returns yet.
    public var returnSeconds: Double?
    public var returnCount: Int

    public init(todayOnTaskSeconds: Double = 0, goalMinutes: Int = 0, streak: Int = 0, bestStreak: Int = 0, restDaysUsed: Int = 0,
                week: [Day] = [], recent: [Digest] = [], bestStretchSeconds: Double = 0, returnSeconds: Double? = nil, returnCount: Int = 0) {
        self.todayOnTaskSeconds = todayOnTaskSeconds; self.goalMinutes = goalMinutes; self.streak = streak; self.bestStreak = bestStreak
        self.restDaysUsed = restDaysUsed; self.week = week; self.recent = recent; self.bestStretchSeconds = bestStretchSeconds
        self.returnSeconds = returnSeconds; self.returnCount = returnCount
    }
}
