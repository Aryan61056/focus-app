import XCTest
@testable import FocusUI
@testable import FocusJudge
@testable import FocusBrain

final class RewardsTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func date(_ day: Int, _ hour: Int = 10) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
    func rec(_ day: Int, _ segs: [(TimelineSegment.Kind, Double)], hour: Int = 10, drifts: Int = 0, returns: [Double]? = nil, practice: Bool? = nil) -> SessionRecord {
        let secs = segs.map { $0.1 * 60 }.reduce(0, +)
        let off = segs.filter { $0.0 == .off }.reduce(0) { $0 + $1.1 } * 60, un = segs.filter { $0.0 == .unsure }.reduce(0) { $0 + $1.1 } * 60
        let start = date(day, hour)
        return SessionRecord(projectId: nil, task: "t", timed: false, start: start, end: start.addingTimeInterval(secs), activeSeconds: secs, offTopicSeconds: off,
                             unsureSeconds: un, drifts: drifts, interrupts: 0, refusals: 0, shadowMarks: 0, segments: segs.map { TimelineSegment($0.0, $0.1 * 60) },
                             returns: returns, practice: practice)
    }
    func focusDay(_ day: Int) -> SessionRecord { rec(day, [(.on, 30)]) }
    func marks(_ s: Rewards.Streak) -> [Rewards.DayMark] { s.week.map(\.mark) }

    // MARK: streak
    func testNoSessionsMeansNoStreak() {
        let s = Rewards.streak([], today: date(10), calendar: cal)
        XCTAssertEqual(s.current, 0); XCTAssertEqual(s.best, 0)
        XCTAssertEqual(marks(s), Array(repeating: .none, count: 7))
    }

    func testConsecutiveFocusDaysBuildAStreakAndTodayCounts() {
        let s = Rewards.streak([focusDay(8), focusDay(9), focusDay(10)], today: date(10), calendar: cal)
        XCTAssertEqual(s.current, 3); XCTAssertEqual(s.best, 3)
        XCTAssertEqual(Array(marks(s).suffix(3)), [.focus, .focus, .focus])
    }

    func testTodayNotYetAFocusDayIsPendingAndNeverBreaksTheStreak() {
        let s = Rewards.streak([focusDay(8), focusDay(9)], today: date(10), calendar: cal)
        XCTAssertEqual(s.current, 2)
        XCTAssertEqual(marks(s).last, .pending)
    }

    func testShortDayDoesNotCountButAFocusDayNeedsOnlyTwentyMinutes() {
        XCTAssertEqual(Rewards.streak([rec(9, [(.on, 19)]), rec(10, [(.on, 20)])], today: date(10), calendar: cal).current, 1)
    }

    func testTwoMissedDaysAreRestDaysAndTheStreakContinues() {
        let s = Rewards.streak([focusDay(3), focusDay(4), focusDay(7)], today: date(7), calendar: cal)   // 5 and 6 missed
        XCTAssertEqual(s.current, 3, "rest days neither count nor break")
        XCTAssertEqual(s.restUsed, 2)
        XCTAssertEqual(marks(s)[4], .rest); XCTAssertEqual(marks(s)[5], .rest)   // days 5 and 6 of the week ending on the 7th
    }

    func testAThirdMissInAWeekEndsTheStreakButKeepsTheBest() {
        let s = Rewards.streak([focusDay(1), focusDay(2), focusDay(3)], today: date(7), calendar: cal)   // 4, 5, 6 missed
        XCTAssertEqual(s.current, 0); XCTAssertEqual(s.best, 3)
        XCTAssertFalse(marks(s).contains(.rest), "days that were only holding a dead streak open show as plain misses")
    }

    func testStartingAgainAfterABreakBeginsANewStreakAndForgetsOldRestDays() {
        let sessions = [focusDay(1), focusDay(2), focusDay(8), focusDay(9)]   // 3..7 missed: streak broke at 5
        let s = Rewards.streak(sessions, today: date(9), calendar: cal)
        XCTAssertEqual(s.current, 2); XCTAssertEqual(s.best, 2)
        XCTAssertEqual(s.restUsed, 0)
    }

    func testDaysBeforeTheFirstSessionAreNotMisses() {
        let s = Rewards.streak([focusDay(9), focusDay(10)], today: date(10), calendar: cal)
        XCTAssertEqual(s.current, 2); XCTAssertEqual(s.restUsed, 0)
        XCTAssertEqual(marks(s).prefix(5), [.none, .none, .none, .none, .none])
    }

    // MARK: goal and stretches
    func testGoalFractionCapsAtOneAndReachedIsExact() {
        let g = Rewards.goal([rec(10, [(.on, 45)])], on: date(10), goalMinutes: 90, calendar: cal)
        XCTAssertEqual(g.fraction, 0.5, accuracy: 1e-9); XCTAssertFalse(g.reached); XCTAssertEqual(g.minutes, 45)
        XCTAssertTrue(Rewards.goal([rec(10, [(.on, 100)])], on: date(10), goalMinutes: 90, calendar: cal).reached)
        XCTAssertEqual(Rewards.goal([rec(10, [(.on, 100)])], on: date(10), goalMinutes: 90, calendar: cal).fraction, 1)
    }

    func testStretchSkipsNotSureButOffTopicAndAwayEndIt() {
        let segs: [TimelineSegment] = [.init(.on, 600), .init(.unsure, 300), .init(.on, 600), .init(.off, 60), .init(.on, 900), .init(.gap, 60), .init(.on, 100)]
        XCTAssertEqual(Rewards.longestStretch(segs), 1200)   // 600 + 600 across the not-sure stretch
        XCTAssertEqual(Rewards.longestStretch([]), 0)
    }

    func testPracticeSessionsAreLeftOutOfStretchesAndReturns() {
        let practice = rec(9, [(.on, 50)], returns: [5, 5, 5], practice: true)
        XCTAssertEqual(Rewards.bestStretch([practice]), 0)
        XCTAssertNil(Rewards.returns([practice], from: date(1), to: date(30)))
        XCTAssertEqual(Rewards.bestStretch([practice, rec(9, [(.on, 12)])]), 12 * 60)
    }

    // MARK: returns
    func testReturnTrendNeedsThreeReturnsInAPeriodAndComparesWithLastWeek() {
        let last = rec(2, [(.on, 30)], returns: [80, 70, 60]), now = rec(9, [(.on, 30)], returns: [40, 30, 20])
        let t = Rewards.returnTrend([last, now], today: date(10), calendar: cal)!
        XCTAssertEqual(t.thisWeek.average, 30, accuracy: 1e-9); XCTAssertEqual(t.lastWeek?.average ?? 0, 70, accuracy: 1e-9)
        XCTAssertNil(Rewards.returnTrend([rec(9, [(.on, 30)], returns: [40, 30])], today: date(10), calendar: cal), "two returns is too few to average")
    }

    // MARK: highlight
    func testLongestStretchBeatsEverythingExceptRough() {
        let older = rec(3, [(.on, 25)])
        let mine = rec(10, [(.on, 40)])
        XCTAssertEqual(Rewards.highlight(for: mine, others: [older], goalMinutes: 30, calendar: cal), .longestStretch(minutes: 40))
    }

    func testFirstSessionEverIsNotARecord() {
        let h = Rewards.highlight(for: rec(10, [(.on, 40)]), others: [], goalMinutes: 90, calendar: cal)
        XCTAssertEqual(h, .noSlips(minutes: 40))
    }

    func testGoalReachedOnlyTheSessionThatCrossesIt() {
        let before = rec(10, [(.on, 50)], hour: 8), crossing = rec(10, [(.on, 45)], hour: 14)
        XCTAssertEqual(Rewards.highlight(for: crossing, others: [before], goalMinutes: 90, calendar: cal), .goalReached)
        let again = rec(10, [(.on, 10)], hour: 18)
        XCTAssertNotEqual(Rewards.highlight(for: again, others: [before, crossing], goalMinutes: 90, calendar: cal), .goalReached)
    }

    func testQuickerReturnNeedsHistoryAndAtLeastTwentyPercentFaster() {
        let usual = rec(5, [(.on, 30)], returns: [60, 60, 60])
        let fast = rec(10, [(.on, 30)], drifts: 2, returns: [30, 20])
        XCTAssertEqual(Rewards.highlight(for: fast, others: [usual], goalMinutes: 0, calendar: cal), .quickerReturn(seconds: 25, usual: 60))
        let same = rec(10, [(.on, 30)], drifts: 2, returns: [55, 60])
        XCTAssertNotEqual(Rewards.highlight(for: same, others: [usual], goalMinutes: 0, calendar: cal), .quickerReturn(seconds: 58, usual: 60))
    }

    func testRoughSessionGetsKindnessNotAScore() {
        let rough = rec(10, [(.on, 8), (.off, 7)], drifts: 5)
        XCTAssertEqual(Rewards.highlight(for: rough, others: [], goalMinutes: 90, calendar: cal), .rough)
    }

    func testShortSessionStillCountsBecauseStartingIsCelebrated() {
        XCTAssertEqual(Rewards.highlight(for: rec(10, [(.on, 4)]), others: [], goalMinutes: 90, calendar: cal), .started)
    }

    // MARK: words
    func testNoRewardOrNudgeTextShoutsOrScoldsOrNamesAThing() {
        var lines = [Rewards.Highlight.longestStretch(minutes: 41), .goalReached, .quickerReturn(seconds: 22, usual: 48), .noSlips(minutes: 25), .started, .rough].map(Rewards.text)
        lines += [Confirmation(kind: .backOnTrack(seconds: 12), at: 0), Confirmation(kind: .backOnTrack(seconds: 300), at: 0), Confirmation(kind: .goalReached, at: 0),
                  Confirmation(kind: .longestStretch(minutes: 30), at: 0)].map(\.text)
        for tone in NudgeTone.allCases { for kind in ["notice", "card"] { for sev in 1...2 { for long in [false, true] {
            lines.append(NudgeCopy.title(kind: kind, severity: sev, tone: tone, task: "Calc homework", longDetour: long))
        } } }
            lines.append(NudgeCopy.gateBody(tone: tone, task: "Calc homework", longDetour: false)); lines.append(NudgeCopy.gateBody(tone: tone, task: "Calc homework", longDetour: true)) }
        for l in lines {
            XCTAssertFalse(l.contains("!"), l); XCTAssertFalse(l.contains("\u{2014}"), l); XCTAssertFalse(l.lowercased().contains("lost"), l)
            XCTAssertFalse(l.lowercased().contains("streak"), "no streak talk in live nudges: \(l)")
        }
    }

    func testEveryNudgeTitleNamesTheTaskExceptTheBreakOffer() {
        for tone in NudgeTone.allCases { for kind in ["notice", "card"] {
            XCTAssertTrue(NudgeCopy.title(kind: kind, severity: 1, tone: tone, task: "Calc homework", longDetour: false).contains("Calc homework"))
        } }
    }

    func testDurationReads() {
        XCTAssertEqual(Rewards.duration(12), "12 s"); XCTAssertEqual(Rewards.duration(180), "3 min"); XCTAssertEqual(Rewards.duration(7200), "2 h"); XCTAssertEqual(Rewards.duration(5400 + 60), "1 h 31 min")
    }

    func testOldSavedSessionsStillLoad() throws {
        let json = #"{"id":"6C0F5E8E-0000-0000-0000-000000000001","task":"x","timed":false,"start":"2026-10-01T10:00:00Z","end":"2026-10-01T10:30:00Z","activeSeconds":1800,"offTopicSeconds":0,"unsureSeconds":0,"drifts":0,"interrupts":0,"refusals":0,"shadowMarks":0,"segments":[],"note":""}"#
        let r = try JSONDecoder.store.decode(SessionRecord.self, from: Data(json.utf8))
        XCTAssertNil(r.returns); XCTAssertNil(r.practice)
    }
}
