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

@MainActor
final class NotchTests: XCTestCase {
    func testRestIsJustTheEarsAndOpenGrowsDownNeverSideways() {
        let rest = NotchLayout.size(.rest, notchWidth: 200, notchHeight: 32)
        XCTAssertEqual(rest.height, 32)
        XCTAssertEqual(rest.width, 200 + 2 * NotchLayout.ear)
        let open = NotchLayout.size(.open, notchWidth: 200, notchHeight: 32)
        XCTAssertGreaterThan(open.height, rest.height)
        XCTAssertGreaterThanOrEqual(open.width, rest.width)
        XCTAssertLessThanOrEqual(open.width, 340, "it grows down; width barely changes")
    }

    func testNoNotchGivesAFloatingPill() {
        let r = NotchLayout.size(.rest, notchWidth: 0, notchHeight: 0)
        XCTAssertEqual(r.height, 36)
        XCTAssertGreaterThan(NotchLayout.size(.nudge, notchWidth: 0, notchHeight: 0).height, r.height)
    }

    func testModeFollowsTheNudgeSurfaceAndNeverTheGate() async {
        var t = 0.0
        let judge = ScriptedJudge(markers: [("youtube", .off), ("Notes", .on)])
        let c = SessionController(judge: judge, now: { t })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        XCTAssertEqual(NotchView(controller: c, notchWidth: 200, notchHeight: 32, openApp: {}).mode, .rest)
        c.windowChanged(WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1"))
        while c.surface == nil && t < 300 { t += 1; c.tick(); await c.waitForJudgments() }
        XCTAssertEqual(NotchView(controller: c, notchWidth: 200, notchHeight: 32, openApp: {}).mode, .nudge)
    }
}

@MainActor
final class ProbeTests: XCTestCase {
    func testProbeCountsDownThenReportsWhatItSawAndClears() async {
        let c = SessionController(judge: ScriptedJudge(markers: []), now: { 0 })
        c.senseNow = { WindowSnapshot(app: "Notes", title: "Calc homework") }
        c.setWindowAccess(.allowed)
        c.runProbe(seconds: 2, tick: 10_000_000)
        try? await Task.sleep(nanoseconds: 5_000_000)
        if case .waiting = c.probe {} else { XCTFail("should be counting down: \(c.probe)") }
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(c.probe, .saw(app: "Notes", title: "Calc homework", trusted: true))
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(c.probe, .idle)
    }

    func testProbeSaysNothingWhenFocusIsInFront() async {
        let c = SessionController(judge: ScriptedJudge(markers: []), now: { 0 })
        c.senseNow = { nil }
        c.runProbe(seconds: 1, tick: 5_000_000)
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(c.probe, .nothing)
    }
}

@MainActor
final class FirstRunTests: XCTestCase {
    func prefs() -> Preferences { Preferences(defaults: UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!) }

    func testLoudnessStepsOnePresetAndNeverPastTheEnds() {
        let p = prefs(); p.preset = .gentle
        p.answerLoudness(.tooLoud); XCTAssertEqual(p.preset, .gentle)
        p.answerLoudness(.tooQuiet); XCTAssertEqual(p.preset, .standard)
        p.answerLoudness(.tooQuiet); XCTAssertEqual(p.preset, .strict)
        p.answerLoudness(.tooQuiet); XCTAssertEqual(p.preset, .strict)
        p.answerLoudness(.tooLoud); XCTAssertEqual(p.preset, .standard)
        p.answerLoudness(.aboutRight); XCTAssertEqual(p.preset, .standard)
        XCTAssertTrue(p.loudnessAsked)
    }

    func testIntroAndLoudnessStartUnseenAndStaySeen() {
        let suite = "focus.tests.\(UUID().uuidString)"
        let a = Preferences(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertFalse(a.introSeen); XCTAssertFalse(a.loudnessAsked)
        a.introSeen = true; a.loudnessAsked = true
        let b = Preferences(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(b.introSeen); XCTAssertTrue(b.loudnessAsked)
    }

    func testTheQuestionIsNotAskedForPracticeSessionsOrQuietOnes() async {
        var t = 0.0
        let c = SessionController(judge: ScriptedJudge(markers: [("youtube", .off), ("Notes", .on)]), now: { t })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: true)
        c.windowChanged(WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1"))
        for _ in 0..<200 { t += 1; c.tick(); await c.waitForJudgments() }
        c.end()
        XCTAssertFalse(c.askLoudness, "practice sessions never nudged")
    }
}
