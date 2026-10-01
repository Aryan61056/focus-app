import XCTest
@testable import FocusUI

final class DayStatsTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))! }
    func rec(_ start: Date, _ segs: [(TimelineSegment.Kind, Double)], drifts: Int = 0) -> SessionRecord {
        let secs = segs.map { $0.1 * 60 }.reduce(0, +)
        let off = segs.filter { $0.0 == .off }.reduce(0) { $0 + $1.1 } * 60, un = segs.filter { $0.0 == .unsure }.reduce(0) { $0 + $1.1 } * 60
        return SessionRecord(projectId: nil, task: "t", timed: false, start: start, end: start.addingTimeInterval(secs), activeSeconds: secs, offTopicSeconds: off, unsureSeconds: un,
                             drifts: drifts, interrupts: 0, refusals: 0, shadowMarks: 0, segments: segs.map { TimelineSegment($0.0, $0.1 * 60) })
    }

    func testSlicesFollowTheClockAndSkipOtherDays() {
        let s = [rec(date(1, 9, 30), [(.on, 30), (.off, 6)]), rec(date(2, 9), [(.on, 60)])]
        let sl = DayStats.slices(s, on: date(1, 12), calendar: cal)
        XCTAssertEqual(sl.count, 2)
        XCTAssertEqual(sl[0].startHour, 9.5, accuracy: 1e-9)
        XCTAssertEqual(sl[1].startHour, 10.0, accuracy: 1e-9)
        XCTAssertEqual(sl[1].kind, .off)
    }

    func testAxisIsEightToEighteenAndWidensToFit() {
        XCTAssertEqual(DayStats.axis(for: []), 8...18)
        let late = [DaySlice(startHour: 19, hours: 2.5, kind: .on)]
        XCTAssertEqual(DayStats.axis(for: late), 8...22)
        let early = [DaySlice(startHour: 6.2, hours: 1, kind: .on)]
        XCTAssertEqual(DayStats.axis(for: early), 6...18)
    }

    func testTotalCountsOnTaskSessionsAndSlips() {
        let s = [rec(date(1, 9), [(.on, 40), (.unsure, 5), (.off, 5)], drifts: 2), rec(date(1, 14), [(.on, 20)], drifts: 0)]
        let t = DayStats.total(s, on: date(1, 20), calendar: cal)
        XCTAssertEqual(t.sessions, 2); XCTAssertEqual(t.slips, 2)
        XCTAssertEqual(t.onTaskSeconds, 60 * 60, accuracy: 1e-6)
    }

    func testWeekIsSevenDaysOldestFirstEndingToday() {
        let s = [rec(date(1, 9), [(.on, 120)]), rec(date(5, 9), [(.on, 60)])]
        let w = DayStats.week(s, endingOn: date(7, 12), calendar: cal)
        XCTAssertEqual(w.count, 7)
        XCTAssertTrue(cal.isDate(w.first!.day, inSameDayAs: date(1, 12)))
        XCTAssertEqual(w[0].hours, 2, accuracy: 1e-9)
        XCTAssertEqual(w[4].hours, 1, accuracy: 1e-9)
        XCTAssertEqual(w[6].hours, 0)
    }
}

extension DayStatsTests {
    func testHeatSplitsAPieceAcrossHoursAndCountsOnlyOnTask() {
        // Thursday 1 Oct 2026, 9:30 start: 45 min on task (30 in hour 9, 15 in hour 10), then 10 min off topic
        let s = [rec(date(1, 9, 30), [(.on, 45), (.off, 10)])]
        let g = DayStats.heat(s, calendar: cal)
        let thursday = 3
        XCTAssertEqual(g[thursday][9], 30 * 60, accuracy: 1e-6)
        XCTAssertEqual(g[thursday][10], 15 * 60, accuracy: 1e-6)
        XCTAssertEqual(g[thursday][11], 0)
        XCTAssertEqual(g.flatMap { $0 }.reduce(0, +), 45 * 60, accuracy: 1e-6)
    }

    func testMorningShareNeedsAnHourOfDataThenReportsPercent() {
        XCTAssertNil(DayStats.morningShare(DayStats.heat([rec(date(1, 9), [(.on, 30)])], calendar: cal)))
        let g = DayStats.heat([rec(date(1, 9), [(.on, 60)]), rec(date(1, 14), [(.on, 60)]), rec(date(2, 10), [(.on, 60)])], calendar: cal)
        XCTAssertEqual(DayStats.morningShare(g), 67)
    }
}
