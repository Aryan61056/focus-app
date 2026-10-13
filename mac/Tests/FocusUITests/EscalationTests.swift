import XCTest
import FocusBrain
import FocusJudge
@testable import FocusUI

@MainActor
final class EscalationPlanTests: XCTestCase {
    func testStepsClimbWithTimeAndGentleHasNoLadder() {
        let p = EscalationPlan.standard
        XCTAssertEqual(p.step(after: 0), .warned)
        XCTAssertEqual(p.step(after: 39), .warned)
        XCTAssertEqual(p.step(after: 40), .checkIn)
        XCTAssertEqual(p.step(after: 100), .pauseScreen)
        XCTAssertEqual(p.step(after: 200), .enforce)
        XCTAssertNil(EscalationPlan.of(.gentle))
        XCTAssertLessThan(EscalationPlan.strict.checkInAfter, p.checkInAfter, "Strict climbs faster")
    }

    func testEnforcementRoundsFireOnceEach() {
        let p = EscalationPlan.standard
        XCTAssertEqual(p.enforceRound(after: 199), 0)
        XCTAssertEqual(p.enforceRound(after: 200), 1)
        XCTAssertEqual(p.enforceRound(after: 319), 1)
        XCTAssertEqual(p.enforceRound(after: 320), 2)
    }

    func testTheGrayFloorOnlyGrows() {
        let f = [EscalationStep.warned, .checkIn, .pauseScreen, .enforce].map(EscalationPlan.veilFloor)
        XCTAssertEqual(f, f.sorted())
        XCTAssertEqual(f.dropFirst().min(), 100, "from the check-in on it is full gray")
    }

    func testFocusAndSystemAppsAreNeverHidden() {
        XCTAssertFalse(Enforcement.canHide("Focus")); XCTAssertFalse(Enforcement.canHide("Finder")); XCTAssertFalse(Enforcement.canHide(nil)); XCTAssertFalse(Enforcement.canHide(" "))
        XCTAssertTrue(Enforcement.canHide("Safari"))
    }

    func testBaselineIsFirmerThanBefore() {
        let p = Preferences(defaults: UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!)
        XCTAssertEqual(p.preset, .standard, "the default used to be Gentle, one quiet note")
        XCTAssertTrue(p.practiceRemoved, "no silent practice sessions by default")
        XCTAssertTrue(p.escalate); XCTAssertTrue(p.screenGrayscale); XCTAssertTrue(p.hideDistractingApp)
    }
}

@MainActor
final class EscalationTests: XCTestCase {
    var t = 0.0
    let judge = CountingJudge { p in Verdict(label: p.contains("youtube") ? .offTask : .onTask) }
    let editor = WindowSnapshot(app: "Notes", title: "Calc homework")
    let video = WindowSnapshot(app: "Safari", title: "clip youtube", url: "https://youtube.com/watch?v=1")
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }
    func make(preset: Preset = .standard, shadow: Bool = false, configure: (SessionController) -> Void = { _ in }) -> SessionController {
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { [unowned self] in self.t })
        configure(c)
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: preset, shadow: shadow)
        return c
    }
    /// Drift onto the video and wait until the brain confirms it. Returns the moment of the warning.
    func driftUntilWarned(_ c: SessionController) async -> Double {
        await advance(c, to: 20)
        c.windowChanged(video)
        while c.presence.state != "interrupted" && t < 300 { await advance(c, to: t + 1) }
        XCTAssertEqual(c.presence.state, "interrupted")
        return t
    }

    func testIgnoringTheWarningClimbsCheckInThenPauseScreenThenHidesTheApp() async {
        var hidden: [String] = [], foreground = 0
        let c = make { $0.onHideApp = { hidden.append($0) }; $0.onForeground = { foreground += 1 } }
        let warned = await driftUntilWarned(c)
        c.act(.dismiss)   // dismissing the card must not stop the climb
        XCTAssertNil(c.checkIn); XCTAssertEqual(c.escalationStep, .warned)

        await advance(c, to: warned + 41)
        XCTAssertNotNil(c.checkIn, "after about 40 s Focus asks whether you are on task")
        XCTAssertEqual(c.escalationStep, .checkIn)

        await advance(c, to: warned + 101)
        XCTAssertTrue(c.escalationGate, "then the pause screen")
        XCTAssertNil(c.checkIn)
        XCTAssertGreaterThan(c.gateHoldRemaining(), 0)
        XCTAssertGreaterThanOrEqual(foreground, 1)
        XCTAssertTrue(hidden.isEmpty)

        await advance(c, to: warned + 201)
        XCTAssertEqual(hidden, ["Safari"], "then the app you drifted into is hidden")
        await advance(c, to: warned + 201 + 120)
        XCTAssertEqual(hidden, ["Safari", "Safari"], "and again every two minutes while you stay away")
    }

    func testEasyExitsAreHeldBackOnThePauseScreenButBackToTaskIsNot() async {
        let c = make()
        let warned = await driftUntilWarned(c)
        await advance(c, to: warned + 101)
        XCTAssertTrue(c.gateOpen)
        c.leaveGate(fine: true)
        XCTAssertTrue(c.gateOpen, "That was fine is disabled during the hold")
        c.leaveGate(fine: false, snooze: true)
        XCTAssertTrue(c.gateOpen, "so is Snooze")
        await advance(c, to: t + 11)
        XCTAssertEqual(c.gateHoldRemaining(), 0)
        c.leaveGate(fine: false)
        XCTAssertFalse(c.gateOpen, "Back to task is always available")
    }

    func testGettingBackToTheTaskEndsTheClimbAndTheGrayClears() async {
        let c = make()
        let warned = await driftUntilWarned(c)
        await advance(c, to: warned + 105)
        XCTAssertTrue(c.escalationGate)
        c.windowChanged(editor)
        await advance(c, to: t + 40)
        XCTAssertEqual(c.escalationStep, .warned)
        XCTAssertFalse(c.escalationGate); XCTAssertNil(c.checkIn)
        XCTAssertEqual(c.veilLevel(), 0, accuracy: 0.5)
    }

    func testAnsweringYesToTheCheckInTeachesTheWindowAndEndsTheClimb() async {
        let c = make()
        let warned = await driftUntilWarned(c)
        await advance(c, to: warned + 41)
        XCTAssertNotNil(c.checkIn)
        c.answerCheckIn(onTask: true)
        XCTAssertNil(c.checkIn); XCTAssertEqual(c.escalationStep, .warned)
        await advance(c, to: t + 30)
        XCTAssertNotEqual(c.presence.state, "interrupted", "the window was forgiven")
    }

    func testTheScreenGraysWithTheClimbAndStaysAtZeroWhenOff() async {
        let c = make()
        let warned = await driftUntilWarned(c)
        await advance(c, to: warned + 60)
        XCTAssertGreaterThanOrEqual(c.veilLevel(), 95, "once the warning is confirmed the screen is fully gray")
        await advance(c, to: warned + 240)
        XCTAssertEqual(c.veilLevel(), 100, accuracy: 0.5)

        t = 0
        let off = make { $0.prefs.screenGrayscale = false }
        let w2 = await driftUntilWarned(off)
        await advance(off, to: w2 + 120)
        XCTAssertEqual(off.veilLevel(), 0)
    }

    func testNoLadderForGentleShadowOrWhenSwitchedOff() async {
        for variant in 0..<3 {
            t = 0
            let c = make(preset: variant == 0 ? .gentle : .standard, shadow: variant == 1, configure: { $0.prefs.escalate = variant != 2 })
            await advance(c, to: 20)
            c.windowChanged(video)
            await advance(c, to: 400)
            XCTAssertNil(c.checkIn, "variant \(variant)"); XCTAssertFalse(c.escalationGate, "variant \(variant)"); XCTAssertEqual(c.escalationStep, .warned, "variant \(variant)")
        }
    }

    func testHidingCanBeSwitchedOffAndPreviewShowsFullGrayBriefly() async {
        var hidden = 0
        let c = make { $0.prefs.hideDistractingApp = false; $0.onHideApp = { _ in hidden += 1 } }
        let warned = await driftUntilWarned(c)
        await advance(c, to: warned + 210)
        XCTAssertEqual(hidden, 0)
        t = 0
        let idle = SessionController(judge: judge, prefs: noWords(), now: { [unowned self] in self.t })
        XCTAssertEqual(idle.veilLevel(), 0)
        idle.previewVeil()
        XCTAssertEqual(idle.veilLevel(), 0, accuracy: 0.1, "the preview starts clear")
        t = 2
        XCTAssertEqual(idle.veilLevel(), 50, accuracy: 0.1, "and fades up, not a jump")
        t = 5
        XCTAssertEqual(idle.veilLevel(), 100)
        t = 8
        XCTAssertEqual(idle.veilLevel(), 50, accuracy: 0.1, "then fades back")
        t = 11
        XCTAssertEqual(idle.veilLevel(), 0)
    }
}

@MainActor
final class VeilFadeTests: XCTestCase {
    var t = 0.0
    let judge = CountingJudge { p in Verdict(label: p.contains("youtube") ? .offTask : .onTask) }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }

    /// Never a jump: from the first flagged moment to the warning, no second changes the gray by more than a few points,
    /// and neither does any second of the climb after it.
    func testTheGrayRisesAndFallsInSmallSteps() async {
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { [unowned self] in self.t })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 20)
        c.windowChanged(WindowSnapshot(app: "Safari", title: "clip youtube", url: "https://youtube.com/watch?v=1"))
        var last = c.veilLevel(), biggest = 0.0, peak = 0.0
        for _ in 0..<420 { await advance(c, to: t + 1); let v = c.veilLevel(); biggest = max(biggest, abs(v - last)); peak = max(peak, v); last = v }
        XCTAssertGreaterThan(peak, 95, "the climb reaches nearly full gray")
        XCTAssertLessThanOrEqual(biggest, 4.5, "no second may change the gray by more than a few points on the way up")
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        last = c.veilLevel(); biggest = 0
        for _ in 0..<60 { await advance(c, to: t + 1); let v = c.veilLevel(); biggest = max(biggest, abs(v - last)); last = v }
        XCTAssertEqual(last, 0, accuracy: 0.5, "it clears after you return")
    }
}
