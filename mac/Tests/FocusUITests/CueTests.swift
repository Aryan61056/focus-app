import XCTest
import FocusBrain
import FocusJudge
@testable import FocusUI

// MARK: pure rules

final class DriftWatchTests: XCTestCase {
    func feed(_ w: inout DriftWatch, _ items: [(Double, Reading.Call, String)]) { for i in items { w.note(call: i.1, key: i.2, at: i.0) } }

    func testSeveralOffReadingsInARowLookLikeARabbitHole() {
        var w = DriftWatch()
        feed(&w, [(0, .on, "a"), (10, .off, "b"), (16, .off, "b")])
        XCTAssertFalse(w.looksLikeARabbitHole(at: 16), "two readings are not enough")
        w.note(call: .off, key: "b", at: 22)
        XCTAssertTrue(w.looksLikeARabbitHole(at: 22))
    }

    func testHoppingBetweenWindowsThatAreOnlyNotSureCountsToo() {
        var w = DriftWatch()
        feed(&w, [(0, .unsure, "a"), (20, .unsure, "b"), (40, .unsure, "c")])
        XCTAssertTrue(w.looksLikeARabbitHole(at: 40), "three different windows, none of them on task")
    }

    func testOneNotSureWindowReadAgainAndAgainIsNotHopping() {
        var w = DriftWatch()
        feed(&w, [(0, .unsure, "a"), (20, .unsure, "a"), (40, .unsure, "a")])
        XCTAssertFalse(w.looksLikeARabbitHole(at: 40))
    }

    func testBeingBackOnTaskOrMostlyOnTaskStopsIt() {
        var w = DriftWatch()
        feed(&w, [(0, .off, "a"), (6, .off, "a"), (12, .off, "a")])
        XCTAssertTrue(w.looksLikeARabbitHole(at: 12))
        w.note(call: .on, key: "t", at: 14)
        XCTAssertFalse(w.looksLikeARabbitHole(at: 14), "the latest reading is on task")
        var m = DriftWatch()
        feed(&m, [(0, .on, "t"), (10, .on, "t"), (20, .on, "t"), (30, .off, "a"), (36, .off, "a"), (42, .off, "a")])
        XCTAssertFalse(m.looksLikeARabbitHole(at: 42), "away readings are not at least twice the on-task ones")
    }

    func testOldReadingsFallOutAndTheCooldownHoldsItBack() {
        var w = DriftWatch()
        feed(&w, [(0, .off, "a"), (6, .off, "a"), (12, .off, "a")])
        XCTAssertFalse(w.looksLikeARabbitHole(at: 200), "all of it is older than the two-minute span")
        w.markNoticed(at: 12)
        w.note(call: .off, key: "a", at: 100); w.note(call: .off, key: "a", at: 106); w.note(call: .off, key: "a", at: 112)
        XCTAssertFalse(w.looksLikeARabbitHole(at: 112), "five minutes between heads-ups")
        w.note(call: .off, key: "a", at: 330); w.note(call: .off, key: "a", at: 336); w.note(call: .off, key: "a", at: 342)
        XCTAssertTrue(w.looksLikeARabbitHole(at: 342))
    }
}

final class DayPressureTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: h, minute: m))! }
    func level(_ minutes: Double, hour h: Int, _ m: Int = 0, goal: Int = 90) -> DayPressure {
        DayPressure.level(goalMinutes: goal, onTaskSeconds: minutes * 60, at: at(h, m), calendar: cal)
    }

    func testMorningIsEasyWhateverYouHaveDone() {
        XCTAssertEqual(level(0, hour: 8), .relaxed)
        XCTAssertEqual(level(0, hour: 11, 59), .relaxed)
    }
    func testReachingTheGoalIsEasyAllDay() {
        XCTAssertEqual(level(90, hour: 17), .relaxed)
        XCTAssertEqual(level(200, hour: 23), .relaxed)
    }
    func testOnPaceIsSteadyAndBehindGetsFirmer() {
        // At 15:00 the pace is two thirds of the goal: 60 of 90 minutes.
        XCTAssertEqual(level(60, hour: 15), .steady)
        XCTAssertEqual(level(50, hour: 15), .behind, "10 minutes behind is under a quarter of the goal")
        XCTAssertEqual(level(20, hour: 15), .wellBehind)
        XCTAssertEqual(level(0, hour: 18), .wellBehind)
        XCTAssertEqual(level(0, hour: 12), .wellBehind, "noon is already a third of the way through the day")
    }
    func testNoGoalMeansNoPace() { XCTAssertEqual(level(0, hour: 17, goal: 0), .steady) }
    func testFirmerLevelsAreQuickerAndHoldLonger() {
        let all: [DayPressure] = [.relaxed, .steady, .behind, .wellBehind]
        XCTAssertEqual(all.map(\.factor), all.map(\.factor).sorted(by: >), "the factor shrinks as the day gets firmer")
        XCTAssertEqual(all.map(\.extraHold), all.map(\.extraHold).sorted())
    }
}

final class RhythmTests: XCTestCase {
    func testPomodoroBreaksAreShortWithALongOneEveryFourth() {
        XCTAssertEqual((1...8).map { Rhythm.breakMinutes(afterBlock: $0) }, [5, 5, 5, 15, 5, 5, 5, 15])
    }
    func testDueTimes() {
        XCTAssertNil(Rhythm.off.dueAfter(checkInMinutes: 25))
        XCTAssertEqual(Rhythm.checkIns.dueAfter(checkInMinutes: 45), 45 * 60)
        XCTAssertEqual(Rhythm.pomodoro.dueAfter(checkInMinutes: 45), 25 * 60, "the check-in interval does not change the work block")
    }
}

final class LadderScaleTests: XCTestCase {
    func testSteadyLeavesTheLadderAlone() {
        XCTAssertEqual(EscalationPlan.standard.scaled(by: 1), .standard)
        XCTAssertEqual(EscalationPlan.strict.scaled(by: 1), .strict)
    }
    func testFirmerIsQuickerInOrderAndHoldsLonger() {
        let p = EscalationPlan.standard.scaled(by: 0.65, extraHold: 10)
        XCTAssertLessThan(p.checkInAfter, EscalationPlan.standard.checkInAfter)
        XCTAssertLessThan(p.checkInAfter, p.pauseAfter); XCTAssertLessThan(p.pauseAfter, p.enforceAfter)
        XCTAssertEqual(p.holdSeconds, 20)
        let tight = EscalationPlan.strict.scaled(by: 0.01)
        XCTAssertGreaterThanOrEqual(tight.checkInAfter, 12); XCTAssertGreaterThan(tight.pauseAfter, tight.checkInAfter); XCTAssertGreaterThan(tight.enforceAfter, tight.pauseAfter)
    }
}

final class CueLayoutTests: XCTestCase {
    let screen = NSRect(x: 0, y: 0, width: 1512, height: 982), visible = NSRect(x: 0, y: 0, width: 1512, height: 950)

    func testCoreGraphicsTopLeftBecomesCocoaBottomLeft() {
        let r = CueLayout.cocoaRect(fromCG: CGRect(x: 100, y: 50, width: 800, height: 600), primaryHeight: 982)
        XCTAssertEqual(r, NSRect(x: 100, y: 332, width: 800, height: 600))
    }
    func testTheBannerSitsNearTheTopOfTheWindowAndStaysOnTheScreen() {
        let win = NSRect(x: 200, y: 200, width: 900, height: 700)
        let f = CueLayout.bannerFrame(content: CGSize(width: 400, height: 46), window: win, screen: screen, visible: visible)
        XCTAssertEqual(f.midX, win.midX, accuracy: 0.5)
        XCTAssertEqual(f.maxY - CueLayout.margin, win.maxY - 38, accuracy: 0.5, "its visible top is a little below the window's top")
        let off = CueLayout.bannerFrame(content: CGSize(width: 400, height: 46), window: NSRect(x: -300, y: 600, width: 500, height: 600), screen: screen, visible: visible)
        XCTAssertGreaterThanOrEqual(off.minX, screen.minX - CueLayout.margin); XCTAssertLessThanOrEqual(off.maxY, screen.maxY)
    }
    func testWithNoWindowTheBannerSitsUnderTheMenuBar() {
        let f = CueLayout.bannerFrame(content: CGSize(width: 400, height: 46), window: nil, screen: screen, visible: visible)
        XCTAssertEqual(f.midX, screen.midX, accuracy: 0.5)
        XCTAssertLessThanOrEqual(f.maxY - CueLayout.margin, visible.maxY)
    }
    func testFrictionCoversABigWindowAndIsACardOtherwise() {
        let big = CueLayout.frictionFrame(card: CGSize(width: 380, height: 300), window: NSRect(x: 100, y: 100, width: 900, height: 700), screen: screen)
        XCTAssertTrue(big.covers); XCTAssertEqual(big.frame, NSRect(x: 100, y: 100, width: 900, height: 700))
        let small = CueLayout.frictionFrame(card: CGSize(width: 380, height: 300), window: NSRect(x: 100, y: 100, width: 300, height: 200), screen: screen)
        XCTAssertFalse(small.covers); XCTAssertEqual(small.frame.midX, screen.midX, accuracy: 0.5)
        XCTAssertFalse(CueLayout.frictionFrame(card: CGSize(width: 380, height: 300), window: nil, screen: screen).covers)
    }
}

final class CueCopyTests: XCTestCase {
    func testNoLineEverNamesTheDistractionOrShoutsOrUsesADash() {
        var lines: [String] = []
        for tone in NudgeTone.allCases { for k in [Banner.Kind.early, .reminder] { lines.append(CueCopy.bannerTitle(k, tone: tone, task: "Calc homework")) } }
        lines += [CueCopy.frictionTitle(task: "Calc homework"), CueCopy.frictionBody(task: "Calc homework")]
        for k in [RhythmPrompt.Kind.checkIn, .breakDue(minutes: 5), .breakDue(minutes: 15)] { lines += [CueCopy.rhythmTitle(k, task: "Calc homework"), CueCopy.rhythmBody(k)] }
        for p in [DayPressure.relaxed, .behind, .wellBehind] { lines += [PaceCopy.line(p, goalReached: true, behindMinutes: 20) ?? "", PaceCopy.line(p, goalReached: false, behindMinutes: 0) ?? ""] }
        for l in lines {
            XCTAssertFalse(l.contains("!"), l); XCTAssertFalse(l.contains("\u{2014}"), l); XCTAssertFalse(l.contains("--"), l)
            XCTAssertFalse(l.lowercased().contains("youtube"), l)
        }
        XCTAssertNil(PaceCopy.line(.steady, goalReached: false, behindMinutes: 0), "steady says nothing")
    }
    func testOnlyTheLoudCuesAreSpoken() {
        XCTAssertNil(CueCopy.spoken(.headsUp, title: "x")); XCTAssertNil(CueCopy.spoken(.friction, title: "x"))
        XCTAssertEqual(CueCopy.spoken(.warning, title: "Back to Calc homework."), "Back to Calc homework.")
    }
}

// MARK: the controller

@MainActor
final class CueControllerTests: XCTestCase {
    var t = 0.0
    var when = Date(timeIntervalSince1970: 1_760_000_000)
    let judge = CountingJudge { p in Verdict(label: p.contains("youtube") ? .offTask : (p.contains("forum") ? .unsure : .onTask)) }
    let editor = WindowSnapshot(app: "Notes", title: "Calc homework")
    let video = WindowSnapshot(app: "Safari", title: "clip youtube", url: "https://youtube.com/watch?v=1")
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }
    func make(preset: Preset = .standard, shadow: Bool = false, configure: (SessionController) -> Void = { _ in }) -> SessionController {
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { [unowned self] in self.t }, date: { [unowned self] in self.when })
        configure(c)
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: preset, shadow: shadow)
        return c
    }
    func driftUntilWarned(_ c: SessionController) async -> Double {
        await advance(c, to: 20)
        c.windowChanged(video)
        while c.presence.state != "interrupted" && t < 300 { await advance(c, to: t + 1) }
        XCTAssertEqual(c.presence.state, "interrupted")
        return t
    }

    // banner and heads-up
    func testTheReminderStaysOverTheDistractionFromTheWarningUntilYouAreBack() async {
        let c = make()
        await advance(c, to: 20)
        XCTAssertNil(c.banner)
        _ = await driftUntilWarned(c)
        XCTAssertEqual(c.banner?.kind, .reminder)
        c.act(.dismiss)   // dismissing the card does not take the reminder away; it is on the window itself
        XCTAssertEqual(c.banner?.kind, .reminder)
        c.windowChanged(editor)
        await advance(c, to: t + 40)
        XCTAssertNil(c.banner, "back on task")
    }

    func testTheCrossHidesTheReminderUntilYouDriftAgain() async {
        let c = make()
        _ = await driftUntilWarned(c)
        c.dismissBanner()
        XCTAssertNil(c.banner)
        await advance(c, to: t + 3)
        XCTAssertNil(c.banner, "it stays hidden while you are still away")
        c.windowChanged(editor); await advance(c, to: t + 40)
        XCTAssertNotEqual(c.presence.state, "interrupted")
        let again = await driftUntilWarned(c)
        XCTAssertGreaterThan(again, 0)
        XCTAssertEqual(c.banner?.kind, .reminder, "a new drift shows it again")
    }

    func testTheBannerNeverAppearsWhenSwitchedOffInPracticeOrDuringThePauseScreen() async {
        let off = make { $0.prefs.showBanner = false }
        _ = await driftUntilWarned(off)
        XCTAssertNil(off.banner)
        t = 0
        let practice = make(shadow: true)
        await advance(practice, to: 20); practice.windowChanged(video); await advance(practice, to: 200)
        XCTAssertNil(practice.banner)
        t = 0
        let c = make()
        let warned = await driftUntilWarned(c)
        await advance(c, to: warned + 101)
        XCTAssertTrue(c.gateOpen)
        XCTAssertNil(c.banner, "the pause screen is up; the banner would only be in the way")
    }

    func testWindowHoppingGetsAHeadsUpBeforeAnyWarningAndItIsGentle() async {
        var haptics: [HapticPattern] = [], bounces = 0, spoken: [String] = []
        let c = make { $0.onHaptic = { haptics.append($0) }; $0.onDockBounce = { bounces += 1 }; $0.onSpeak = { spoken.append($0) }; $0.prefs.speakNudges = true }
        await advance(c, to: 20)
        var n = 0
        while c.banner == nil && c.presence.state != "interrupted" && t < 200 {
            n += 1
            c.windowChanged(WindowSnapshot(app: "Safari", title: "clip youtube \(n)", url: "https://youtube.com/watch?v=\(n)"))
            await advance(c, to: t + 8)
        }
        XCTAssertEqual(c.banner?.kind, .early, "the heads-up arrives while the brain has not warned yet")
        XCTAssertNotEqual(c.presence.state, "interrupted")
        XCTAssertEqual(haptics.first, .light, "a light tap, not the firm one")
        XCTAssertEqual(bounces, 0, "no Dock bounce for a heads-up")
        XCTAssertTrue(spoken.isEmpty, "and it is never spoken")
        XCTAssertEqual(c.menuCue, .headsUp)
    }

    func testTheHeadsUpFadesAfterAFewSecondsAndWaitsBeforeComingBack() async {
        let c = make()
        await advance(c, to: 20)
        var n = 0
        while c.banner == nil && t < 200 { n += 1; c.windowChanged(WindowSnapshot(app: "Safari", title: "clip youtube \(n)")); await advance(c, to: t + 8) }
        XCTAssertEqual(c.banner?.kind, .early)
        c.windowChanged(editor)   // back at once
        await advance(c, to: t + SessionController.headsUpSeconds + 2)
        XCTAssertNil(c.banner)
    }

    func testThisIsPartOfItTeachesTheWindowAndHidesTheHeadsUp() async {
        let c = make()
        await advance(c, to: 20)
        var n = 0
        while c.banner == nil && t < 200 { n += 1; c.windowChanged(WindowSnapshot(app: "Safari", title: "clip youtube \(n)")); await advance(c, to: t + 8) }
        XCTAssertNotNil(c.banner)
        c.bannerPartOfIt()
        XCTAssertNil(c.banner)
        XCTAssertFalse(c.learnedRules.isEmpty, "the window was learned")
    }

    func testNoHeadsUpInGentleOrWhenItsSwitchOrTheBannerIsOff() async {
        for variant in 0..<3 {
            t = 0
            let c = make(preset: variant == 0 ? .gentle : .standard) { if variant == 1 { $0.prefs.headsUp = false }; if variant == 2 { $0.prefs.showBanner = false } }
            await advance(c, to: 20)
            for n in 1...6 { c.windowChanged(WindowSnapshot(app: "Safari", title: "clip youtube \(n)")); await advance(c, to: t + 8); XCTAssertNotEqual(c.banner?.kind, .early, "variant \(variant)") }
        }
    }

    // the cues
    func testTheWarningUsesTheFirmTapTheDockAndTheVoiceButOnlyOnceInFifteenSeconds() async {
        var haptics: [HapticPattern] = [], bounces = 0, spoken: [String] = []
        let c = make { $0.onHaptic = { haptics.append($0) }; $0.onDockBounce = { bounces += 1 }; $0.onSpeak = { spoken.append($0) }; $0.prefs.speakNudges = true }
        _ = await driftUntilWarned(c)
        XCTAssertTrue(haptics.contains(.firm)); XCTAssertGreaterThanOrEqual(bounces, 1)
        XCTAssertEqual(spoken.count, 1)
        XCTAssertFalse(spoken[0].contains("youtube"), "the voice never names what you were looking at")
        XCTAssertEqual(c.menuCue, .away)
    }

    func testTheVoiceIsOffByDefaultAndEveryCueRespectsItsSwitch() async {
        var haptics = 0, bounces = 0, spoken = 0
        let c = make { $0.onHaptic = { _ in haptics += 1 }; $0.onDockBounce = { bounces += 1 }; $0.onSpeak = { _ in spoken += 1 }
            $0.prefs.hapticTap = false; $0.prefs.dockBounce = false; $0.prefs.menuBarCue = false }
        XCTAssertFalse(c.prefs.speakNudges)
        _ = await driftUntilWarned(c)
        XCTAssertEqual(haptics, 0); XCTAssertEqual(bounces, 0); XCTAssertEqual(spoken, 0)
        XCTAssertEqual(c.menuCue, .none)
    }

    func testPracticeModeIsSilentInEveryChannel() async {
        var any = 0
        let c = make(shadow: true) { $0.onHaptic = { _ in any += 1 }; $0.onDockBounce = { any += 1 }; $0.onSpeak = { _ in any += 1 }; $0.prefs.speakNudges = true }
        await advance(c, to: 20); c.windowChanged(video); await advance(c, to: 300)
        XCTAssertEqual(any, 0); XCTAssertEqual(c.menuCue, .none)
    }

    func testTheLadderStepsEachGetACue() async {
        var haptics = 0
        let c = make { $0.onHaptic = { _ in haptics += 1 } }
        let warned = await driftUntilWarned(c)
        let atWarning = haptics
        await advance(c, to: warned + 41); XCTAssertGreaterThan(haptics, atWarning, "the check-in")
        let atCheckIn = haptics
        await advance(c, to: warned + 101); XCTAssertGreaterThan(haptics, atCheckIn, "the pause screen")
    }

    // friction
    func goThroughThePauseScreen(_ c: SessionController) async {
        let warned = await driftUntilWarned(c)
        await advance(c, to: warned + 101)
        XCTAssertTrue(c.escalationGate)
        await advance(c, to: t + 11)
        c.leaveGate(fine: false)
        XCTAssertFalse(c.gateOpen)
    }

    func testReopeningTheSameSiteAfterThePauseScreenAsksForAMoment() async {
        let c = make()
        await goThroughThePauseScreen(c)
        c.windowChanged(editor)
        XCTAssertNil(c.friction)
        await advance(c, to: t + 30)
        c.windowChanged(video)
        XCTAssertEqual(c.friction?.app, "Safari")
        XCTAssertEqual(c.menuCue, .headsUp)
        c.windowChanged(editor)
        XCTAssertNil(c.friction, "leaving the site clears it")
    }

    func testADifferentSiteInTheSameBrowserIsNotAskedAbout() async {
        let c = make()
        await goThroughThePauseScreen(c)
        c.windowChanged(WindowSnapshot(app: "Safari", title: "Calc reference", url: "https://docs.example.com/calc"))
        XCTAssertNil(c.friction, "the key is the site, not the browser")
    }

    func testHoldingForFiveSecondsOpensItForTenMinutesAndLettingGoStartsOver() async {
        let c = make()
        await goThroughThePauseScreen(c)
        c.windowChanged(editor); await advance(c, to: t + 30)
        c.windowChanged(video)
        XCTAssertNotNil(c.friction)
        c.beginFrictionHold(); t += 3
        XCTAssertEqual(c.frictionHoldProgress(), 0.6, accuracy: 0.01)
        c.endFrictionHold()
        XCTAssertEqual(c.frictionHoldProgress(), 0)
        c.updateFrictionHold(); XCTAssertNotNil(c.friction, "letting go early opens nothing")
        c.beginFrictionHold(); t += 5.1
        c.updateFrictionHold()
        XCTAssertNil(c.friction)
        c.windowChanged(editor); c.windowChanged(video)
        XCTAssertNil(c.friction, "no second ask during the pass")
        t += Friction.passSeconds + 1
        c.windowChanged(editor); c.windowChanged(video)
        XCTAssertNotNil(c.friction, "the pass ran out")
    }

    func testATypedReasonOpensItForTheSessionAndCountsAsThatWasFine() async {
        let c = make()
        await goThroughThePauseScreen(c)
        c.windowChanged(editor); await advance(c, to: t + 30)
        c.windowChanged(video)
        XCTAssertFalse(c.submitFrictionReason("no"), "too short")
        XCTAssertFalse(c.submitFrictionReason("because"), "one word")
        XCTAssertNotNil(c.friction)
        XCTAssertTrue(c.submitFrictionReason("a lecture on integrals"))
        XCTAssertNil(c.friction)
        t += 5000
        c.windowChanged(editor); c.windowChanged(video)
        XCTAssertNil(c.friction, "for the rest of the session")
    }

    func testBackToTaskOnTheFrictionPanelDoesNotAskAgainAtOnce() async {
        let c = make()
        await goThroughThePauseScreen(c)
        c.windowChanged(editor); await advance(c, to: t + 30)
        c.windowChanged(video)
        c.frictionBackToTask()
        XCTAssertNil(c.friction)
        c.windowChanged(video)
        XCTAssertNil(c.friction, "the task app needs a moment to come forward")
    }

    func testFrictionCanBeSwitchedOffAndNeverRunsInPractice() async {
        let c = make { $0.prefs.frictionReturn = false }
        await goThroughThePauseScreen(c)
        c.windowChanged(video); XCTAssertNil(c.friction)
    }

    func testSayingThatWasFineOnThePauseScreenDoesNotBlockTheSite() async {
        let c = make()
        let warned = await driftUntilWarned(c)
        await advance(c, to: warned + 101 + 11)
        c.leaveGate(fine: true)
        c.windowChanged(editor); c.windowChanged(video)
        XCTAssertNil(c.friction)
    }

    // rhythm
    func testCheckInsComeAtTheIntervalAndIgnoringOneCountsAsYes() async {
        let c = make { $0.prefs.rhythm = .checkIns; $0.prefs.checkInMinutes = 15 }
        await advance(c, to: 15 * 60 - 1)
        XCTAssertNil(c.rhythmPrompt)
        await advance(c, to: 15 * 60 + 1)
        XCTAssertEqual(c.rhythmPrompt?.kind, .checkIn)
        await advance(c, to: t + 91)
        XCTAssertNil(c.rhythmPrompt, "ignored for 90 seconds is a yes")
        await advance(c, to: t + 15 * 60 - 91)
        XCTAssertNil(c.rhythmPrompt, "a new interval starts when the last one ends")
        await advance(c, to: t + 100)
        XCTAssertNotNil(c.rhythmPrompt)
    }

    func testPomodoroOffersABreakAfterTwentyFiveMinutesAndTheBreakPausesTheBrain() async {
        let c = make { $0.prefs.rhythm = .pomodoro }
        await advance(c, to: 25 * 60 + 1)
        XCTAssertEqual(c.rhythmPrompt?.kind, .breakDue(minutes: 5))
        c.rhythmTakeBreak()
        XCTAssertNil(c.rhythmPrompt)
        XCTAssertEqual(c.presence.state, "paused"); XCTAssertEqual(c.presence.reason, "break")
        XCTAssertEqual(c.workBlocks, 1)
        await advance(c, to: t + 5 * 60 + 5)
        XCTAssertNotEqual(c.presence.state, "paused", "the break ended by itself")
        await advance(c, to: t + 24 * 60)
        XCTAssertNil(c.rhythmPrompt, "the break time does not count as work")
        await advance(c, to: t + 90)
        XCTAssertEqual(c.rhythmPrompt?.kind, .breakDue(minutes: 5))
    }

    func testTheFourthBreakIsLongAndFiveMoreMinutesPutsItOff() async {
        let c = make { $0.prefs.rhythm = .pomodoro }
        c.workBlocks = 3
        await advance(c, to: 25 * 60 + 1)
        XCTAssertEqual(c.rhythmPrompt?.kind, .breakDue(minutes: 15))
        c.rhythmKeepGoing()
        XCTAssertNil(c.rhythmPrompt)
        await advance(c, to: t + 5 * 60 - 2)
        XCTAssertNil(c.rhythmPrompt)
        await advance(c, to: t + 5)
        XCTAssertNotNil(c.rhythmPrompt)
    }

    func testAPromptWaitsWhileYouAreBeingWarnedOrPaused() async {
        let c = make { $0.prefs.rhythm = .checkIns; $0.prefs.checkInMinutes = 15 }
        await advance(c, to: 14 * 60 + 40)
        c.windowChanged(video)
        while c.presence.state != "interrupted" && t < 15 * 60 + 200 { await advance(c, to: t + 1) }
        XCTAssertEqual(c.presence.state, "interrupted")
        XCTAssertNil(c.rhythmPrompt, "not on top of a warning")
        c.windowChanged(editor)
        await advance(c, to: t + 40)
        XCTAssertNotNil(c.rhythmPrompt, "it comes once you are working again")
    }

    func testRhythmIsOffByDefaultAndSilentInPractice() async {
        let c = make()
        XCTAssertEqual(c.prefs.rhythm, .off)
        await advance(c, to: 40 * 60); XCTAssertNil(c.rhythmPrompt)
        t = 0
        let p = make(shadow: true) { $0.prefs.rhythm = .pomodoro }
        await advance(p, to: 30 * 60); XCTAssertNil(p.rhythmPrompt)
    }

    func testAPromptUsesTheLoudChannelsAndLightsTheMenuBar() async {
        var bounces = 0, spoken: [String] = []
        let c = make { $0.prefs.rhythm = .pomodoro; $0.onDockBounce = { bounces += 1 }; $0.onSpeak = { spoken.append($0) }; $0.prefs.speakNudges = true }
        await advance(c, to: 25 * 60 + 1)
        XCTAssertEqual(bounces, 1); XCTAssertEqual(spoken, ["Time for a 5 minute break"])
        XCTAssertEqual(c.menuCue, .headsUp)
    }

    // pressure
    func at(_ h: Int) -> Date {
        var cal = Calendar.current; cal.timeZone = .current
        return cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: h))!
    }

    func testTheLadderIsSlowerInTheMorningAndQuickerWhenBehind() async {
        when = at(10)
        let morning = make { $0.prefs.paceMatters = true }
        XCTAssertEqual(morning.pressure, .relaxed)
        let warnedAM = await driftUntilWarned(morning)
        await advance(morning, to: warnedAM + 41)
        XCTAssertNil(morning.checkIn, "40 seconds is not enough in the morning: the check-in waits 50")
        await advance(morning, to: warnedAM + 51)
        XCTAssertNotNil(morning.checkIn)

        t = 0; when = at(17)
        let late = make { $0.prefs.paceMatters = true }
        XCTAssertEqual(late.pressure, .wellBehind)
        let warnedPM = await driftUntilWarned(late)
        await advance(late, to: warnedPM + 27)
        XCTAssertNotNil(late.checkIn, "behind the pace, the check-in comes after about 26 seconds")
        await advance(late, to: warnedPM + 66)
        XCTAssertTrue(late.escalationGate)
        XCTAssertGreaterThan(late.gateHoldRemaining(), 10, "and the pause screen holds the easy exits longer")
    }

    func testPaceCanBeSwitchedOffOrHiddenWithTheGoal() {
        when = at(17)
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { [unowned self] in self.t }, date: { [unowned self] in self.when })
        XCTAssertEqual(c.pressure, .steady, "noWords() turns the pace off")
        c.prefs.paceMatters = true
        XCTAssertEqual(c.pressure, .wellBehind)
        XCTAssertNotNil(c.paceLine)
        c.prefs.showProgress = false
        XCTAssertEqual(c.pressure, .steady, "a goal you cannot see does not push")
        XCTAssertNil(c.paceLine)
    }

    func testTheShippedDefaultsHaveTheQuietCuesOnAndTheVoiceAndScheduleOff() {
        let p = Preferences(defaults: UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!)
        XCTAssertTrue(p.showBanner); XCTAssertTrue(p.headsUp); XCTAssertTrue(p.menuBarCue); XCTAssertTrue(p.dockBounce)
        XCTAssertTrue(p.hapticTap); XCTAssertTrue(p.frictionReturn); XCTAssertTrue(p.paceMatters)
        XCTAssertFalse(p.speakNudges); XCTAssertEqual(p.rhythm, .off); XCTAssertEqual(p.checkInMinutes, 25)
    }
}
