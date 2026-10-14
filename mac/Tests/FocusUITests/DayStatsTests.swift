import XCTest
@testable import FocusUI
@testable import FocusJudge
@testable import FocusBrain

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
    /// Droppy's proportions (owner asked for them, 2026-10-13): hover widens the ears a little, a click opens a wide card.
    func testRestIsJustTheEarsHoverWidensAndOpenIsAWideCard() {
        let rest = NotchLayout.size(.rest, notchWidth: 200, notchHeight: 32)
        XCTAssertEqual(rest.height, 32)
        XCTAssertEqual(rest.width, 200 + 2 * NotchLayout.ear)
        let peek = NotchLayout.size(.peek, notchWidth: 200, notchHeight: 32)
        XCTAssertGreaterThan(peek.width, rest.width)
        XCTAssertLessThanOrEqual(peek.height - rest.height, 4, "hover widens; it barely grows down")
        let open = NotchLayout.size(.open, notchWidth: 200, notchHeight: 32)
        XCTAssertGreaterThan(open.height, peek.height + 80)
        XCTAssertGreaterThanOrEqual(open.width, peek.width)
        let box = NotchLayout.panelSize(notchWidth: 200, notchHeight: 32)
        XCTAssertGreaterThanOrEqual(box.width, open.width); XCTAssertGreaterThanOrEqual(box.height, open.height)
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
        XCTAssertEqual(NotchView(controller: c, notchWidth: 200, notchHeight: 32).mode, .rest)
        c.windowChanged(WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1"))
        while c.surface == nil && t < 300 { t += 1; c.tick(); await c.waitForJudgments() }
        XCTAssertEqual(NotchView(controller: c, notchWidth: 200, notchHeight: 32).mode, .nudge)
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
        let c = SessionController(judge: ScriptedJudge(markers: [("youtube", .off), ("Notes", .on)]), prefs: noWords(), now: { t })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: true)
        c.windowChanged(WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1"))
        for _ in 0..<200 { t += 1; c.tick(); await c.waitForJudgments() }
        c.end()
        XCTAssertFalse(c.askLoudness, "practice sessions never nudged")
    }
}

@MainActor
final class LevelZeroStartTests: XCTestCase {
    func testStartSheetOffersTheProjectWorkedOnLast() {
        let store = DataStore()
        var a = store.addProject(name: "Essay"); a.nextStep = "Add citations"; store.update(a)
        let b = store.addProject(name: "Calc homework")
        let t = Date()
        store.record(SessionRecord(projectId: a.id, task: a.name, timed: false, start: t.addingTimeInterval(-7200), end: t.addingTimeInterval(-3600), activeSeconds: 3600, offTopicSeconds: 0, unsureSeconds: 0, drifts: 0, interrupts: 0, refusals: 0, shadowMarks: 0, segments: []))
        store.record(SessionRecord(projectId: b.id, task: b.name, timed: false, start: t.addingTimeInterval(-1800), end: t, activeSeconds: 1800, offTopicSeconds: 0, unsureSeconds: 0, drifts: 0, interrupts: 0, refusals: 0, shadowMarks: 0, segments: []))
        XCTAssertEqual(StartSheet.lastProject(store)?.name, "Calc homework")
        XCTAssertNil(StartSheet.lastProject(DataStore()))
        XCTAssertNil(StartSheet.lastProject(nil))
    }
}

@MainActor
final class BringBackTests: XCTestCase {
    func testBackToTaskNamesTheAppTheUserWasOnTaskIn() async {
        var t = 0.0
        let c = SessionController(judge: ScriptedJudge(markers: [("youtube", .off), ("Notes", .on)]), now: { t })
        var brought: [String] = []
        c.onBringBackToApp = { brought.append($0) }
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        for _ in 0..<5 { t += 1; c.tick(); await c.waitForJudgments() }
        c.windowChanged(WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1"))
        while c.surface == nil && t < 300 { t += 1; c.tick(); await c.waitForJudgments() }
        c.act(.backToTask)
        XCTAssertEqual(brought.last, "Notes")
    }
}

@MainActor
final class MenuRequestTests: XCTestCase {
    func testRepeatedSectionRequestsAreDistinct() {
        let c = SessionController(judge: ScriptedJudge(markers: []), now: { 0 })
        c.requestSection(.history); let a = c.sectionRequest!
        c.requestSection(.history); let b = c.sectionRequest!
        XCTAssertEqual(a.section, .history); XCTAssertNotEqual(a.serial, b.serial)
        c.requestStart(); XCTAssertEqual(c.startRequests, 1)
    }
}

@MainActor
final class StoreSafetyTests: XCTestCase {
    func testAnUnreadableStoreIsSetAsideNotOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("focus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("store.json")
        try Data("{ not json".utf8).write(to: url)
        let s = DataStore(url: url)
        s.addProject(name: "New")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("store.unreadable-") }, "the bad file is kept: \(files)")
        XCTAssertEqual(DataStore(url: url).projects.map(\.name), ["New"])
        try? FileManager.default.removeItem(at: dir)
    }
}

@MainActor
final class NextStepTests: XCTestCase {
    func testSavingTheNextStepKeepsItOnTheProject() {
        let store = DataStore()
        let c = SessionController(judge: ScriptedJudge(markers: [("Notes", .on)]), store: store, now: { 0 })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        c.saveNextStep("  Check problem 4  ")
        XCTAssertEqual(store.projectNamed("Calc homework").nextStep, "Check problem 4")
    }
}

final class JudgeStatusTests: XCTestCase {
    func testReasonsBecomePlainWords() {
        XCTAssertTrue(JudgeStatus.friendly("appleIntelligenceNotEnabled").contains("turned off"))
        XCTAssertTrue(JudgeStatus.friendly("deviceNotEligible").contains("cannot run"))
        XCTAssertTrue(JudgeStatus.friendly("modelNotReady").contains("downloading"))
        XCTAssertFalse(JudgeStatus.friendly("somethingNew").isEmpty)
    }
}

@MainActor
final class ContextTipTests: XCTestCase {
    func testTipAppearsOnlyWhenMostlyUnsureAndUndescribedAndOnlyOnce() async {
        var t = 0.0
        let store = DataStore()
        let c = SessionController(judge: ScriptedJudge(markers: []), store: store, now: { t })   // everything "unsure"
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        XCTAssertFalse(c.showContextTip, "too early")
        for i in 0..<8 {
            c.windowChanged(WindowSnapshot(app: "App\(i)", title: "Window \(i)"))
            for _ in 0..<15 { t += 1; c.tick(); await c.waitForJudgments() }
        }
        XCTAssertTrue(c.showContextTip)
        c.prefs.contextTipDismissed = true
        XCTAssertFalse(c.showContextTip)
    }
}

@MainActor
final class MatchingWordsTests: XCTestCase {
    struct NeverCalled: Judge {
        func reasonFirst(prompt: String) async -> Verdict { XCTFail("the model should not be asked"); return Verdict(label: .unsure) }
        func relation(prompt: String) async -> Verdict { XCTFail("the model should not be asked"); return Verdict(label: .unsure) }
    }

    func testAWindowSharingTaskWordsIsSettledWithoutTheModelAndCanBeTurnedOff() async {
        var t = 0.0
        let c = SessionController(judge: NeverCalled(), now: { t })
        c.windowChanged(WindowSnapshot(app: "Code", title: "orders_api.py - orders-service"))
        c.begin(task: "Fix the pagination bug in the orders API", preset: .standard, shadow: false)
        for _ in 0..<30 { t += 1; c.tick(); await c.waitForJudgments() }
        XCTAssertEqual(c.latest?.call, .on); XCTAssertEqual(c.latest?.byWords, true)
        XCTAssertTrue(c.latest?.reason.contains("orders") ?? false)
        XCTAssertEqual(c.stats.model, 0); XCTAssertGreaterThan(c.stats.rule, 0)
    }

    func testTurnedOffTheModelDecidesAgain() async {
        var t = 0.0
        let c = SessionController(judge: ScriptedJudge(markers: [("orders", .on)]), now: { t })
        c.prefs.matchTaskWords = false
        c.windowChanged(WindowSnapshot(app: "Code", title: "orders_api.py - orders-service"))
        c.begin(task: "Fix the pagination bug in the orders API", preset: .standard, shadow: false)
        for _ in 0..<5 { t += 1; c.tick(); await c.waitForJudgments() }
        XCTAssertEqual(c.latest?.byWords, false); XCTAssertGreaterThan(c.stats.model, 0)
    }
}

/// Most tests use windows titled like the task. The matching-words rule would settle those without the model, so they opt out.
@MainActor func noWords() -> Preferences {
    let p = Preferences(defaults: UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!); p.matchTaskWords = false
    // The shipped default has no practice mode; these tests were written for it, so they opt back in (a test asks for `shadow: false` to leave it).
    p.practiceRemoved = false; p.restartPractice()
    // Likewise the original check timing and confidence bar; tests of the shipped defaults build their own Preferences.
    p.checkRate = .normal; p.sensitivity = .careful
    // And no time-of-day pace, so the timing does not depend on the hour the tests run at.
    p.paceMatters = false
    return p
}

final class ClockTests: XCTestCase {
    func testTheClockCountsSleepSoALongSleepLooksLong() {
        let a = SessionController.clock(), b = SessionController.clock()
        XCTAssertGreaterThanOrEqual(b, a)
        // It is never behind systemUptime, which excludes sleep; on a Mac that has slept since boot it is ahead.
        XCTAssertGreaterThanOrEqual(SessionController.clock() + 1, ProcessInfo.processInfo.systemUptime)
    }
}

final class StartParseTests: XCTestCase {
    func testTrailingMinutesStartATimedSession() {
        XCTAssertEqual(StartSheet.parse("Calc homework 50").task, "Calc homework"); XCTAssertEqual(StartSheet.parse("Calc homework 50").minutes, 50)
        XCTAssertEqual(StartSheet.parse("essay 25 min").minutes, 25); XCTAssertEqual(StartSheet.parse("essay 25 minutes").task, "essay")
    }
    func testNumbersThatAreNotDurationsStayInTheTask() {
        XCTAssertNil(StartSheet.parse("Chapter 3").minutes, "3 is below the 5 minute floor")
        XCTAssertNil(StartSheet.parse("Study for exam 2026").minutes)
        XCTAssertEqual(StartSheet.parse("Study for exam 2026").task, "Study for exam 2026")
        XCTAssertNil(StartSheet.parse("50").minutes, "a bare number is a task, not a duration")
        XCTAssertNil(StartSheet.parse("").minutes)
    }
}
