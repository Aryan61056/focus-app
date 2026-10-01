import Foundation

public struct DaySlice: Equatable, Sendable {
    public var startHour: Double, hours: Double
    public var kind: TimelineSegment.Kind
}

/// Pure chart maths over saved sessions, kept apart from the views so it can be tested. Seconds only; no text.
public enum DayStats {
    static func hourOfDay(_ d: Date, _ cal: Calendar) -> Double {
        let c = cal.dateComponents([.hour, .minute, .second], from: d)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    /// Timeline pieces for one day, in clock hours, so a track can lay sessions out along the day.
    public static func slices(_ sessions: [SessionRecord], on day: Date, calendar cal: Calendar = .current) -> [DaySlice] {
        var out: [DaySlice] = []
        for s in sessions.sorted(by: { $0.start < $1.start }) where cal.isDate(s.start, inSameDayAs: day) {
            var cursor = hourOfDay(s.start, cal)
            for seg in s.segments { let h = seg.seconds / 3600; out.append(DaySlice(startHour: cursor, hours: h, kind: seg.kind)); cursor += h }
        }
        return out
    }

    /// The hours the day track should span: 8 to 18 by default, widened to fit anything outside it.
    public static func axis(for slices: [DaySlice]) -> ClosedRange<Int> {
        let lo = min(8, Int((slices.map(\.startHour).min() ?? 8).rounded(.down)))
        let hi = max(18, Int((slices.map { $0.startHour + $0.hours }.max() ?? 18).rounded(.up)))
        return lo...min(24, hi)
    }

    public struct Total: Equatable, Sendable { public var onTaskSeconds: Double; public var sessions: Int; public var slips: Int }

    public static func total(_ sessions: [SessionRecord], on day: Date, calendar cal: Calendar = .current) -> Total {
        let s = sessions.filter { cal.isDate($0.start, inSameDayAs: day) }
        return Total(onTaskSeconds: s.reduce(0) { $0 + $1.onTaskSeconds }, sessions: s.count, slips: s.reduce(0) { $0 + $1.drifts })
    }

    /// On-task hours for the seven days ending on `day`, oldest first.
    public static func week(_ sessions: [SessionRecord], endingOn day: Date, calendar cal: Calendar = .current) -> [(day: Date, hours: Double)] {
        (0..<7).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: day) else { return nil }
            return (d, total(sessions, on: d, calendar: cal).onTaskSeconds / 3600)
        }
    }

    /// On-task seconds by weekday (0 = Monday) and clock hour, with a piece that crosses an hour split between the hours.
    public static func heat(_ sessions: [SessionRecord], calendar cal: Calendar = .current) -> [[Double]] {
        var grid = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        for s in sessions {
            let wd = (cal.component(.weekday, from: s.start) + 5) % 7   // Sunday = 1 in Calendar, so Monday becomes 0
            var cursor = hourOfDay(s.start, cal)
            for seg in s.segments {
                var left = seg.seconds / 3600
                while left > 1e-9 {
                    let hour = Int(cursor)
                    if hour > 23 { break }
                    let take = min(left, Double(hour + 1) - cursor)
                    if seg.kind == .on { grid[wd][hour] += take * 3600 }
                    cursor += take; left -= take
                }
            }
        }
        return grid
    }

    /// Share of on-task time that happened before noon, or nil when there is nothing to say.
    public static func morningShare(_ grid: [[Double]]) -> Int? {
        let all = grid.flatMap { $0 }.reduce(0, +)
        guard all >= 3600 else { return nil }
        let morning = grid.flatMap { $0[0..<12] }.reduce(0, +)
        return Int((morning / all * 100).rounded())
    }
}
