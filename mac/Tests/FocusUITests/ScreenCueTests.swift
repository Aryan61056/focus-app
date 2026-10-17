import XCTest
import AppKit
@testable import FocusUI
import FocusJudge

/// The closing-in edges and the landing ring: new, optional cues around the same drift (docs/NUDGE-IDEAS.md).
final class VignetteMathTests: XCTestCase {
    func testTheEdgesDarkenAndTheClearMiddleShrinksAsTheLevelRises() {
        var last = Vignette.shape(0)
        XCTAssertEqual(last.edgeAlpha, 0, "nothing at level 0")
        for p in stride(from: 5.0, through: 100.0, by: 5.0) {
            let s = Vignette.shape(p)
            XCTAssertGreaterThan(s.edgeAlpha, last.edgeAlpha); XCTAssertLessThan(s.clearUntil, last.clearUntil)
            last = s
        }
        XCTAssertEqual(Vignette.shape(100).clearUntil, 0.40, accuracy: 0.001, "the middle stays readable even at the top")
        XCTAssertLessThanOrEqual(Vignette.shape(100).edgeAlpha, 0.75, "and the edges never go fully black")
    }

    func testOutOfRangeLevelsAreClamped() {
        XCTAssertEqual(Vignette.shape(-20).edgeAlpha, 0)
        XCTAssertEqual(Vignette.shape(400).edgeAlpha, Vignette.shape(100).edgeAlpha)
    }
}

@MainActor
final class EdgeCueTests: XCTestCase {
    var t = 0.0
    let judge = CountingJudge { p in Verdict(label: p.contains("youtube") ? .offTask : .onTask) }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }
    func make(_ configure: (Preferences) -> Void = { _ in }) -> SessionController {
        let prefs = noWords(); configure(prefs)
        let c = SessionController(judge: judge, store: DataStore(), prefs: prefs, now: { [unowned self] in self.t })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        return c
    }
    func drift(_ c: SessionController) async {
        await advance(c, to: 20)
        c.windowChanged(WindowSnapshot(app: "Safari", title: "clip youtube", url: "https://youtube.com/watch?v=1"))
        await advance(c, to: 200)
    }

    func testTheEdgesAreOffUntilYouAskForThem() async {
        XCTAssertFalse(noWords().screenEdges)
        let c = make()
        await drift(c)
        XCTAssertGreaterThan(c.veilLevel(), 90, "the gray is on by default")
        XCTAssertEqual(c.edgeLevel(), 0)
    }

    func testTheEdgesFollowTheSameDriftAsTheGray() async {
        let c = make { $0.screenEdges = true }
        await drift(c)
        XCTAssertEqual(c.edgeLevel(), c.veilLevel(), accuracy: 0.001)
        XCTAssertGreaterThan(c.edgeLevel(), 90)
    }

    func testTheEdgesWorkWithoutTheGray() async {
        let c = make { $0.screenEdges = true; $0.screenGrayscale = false }
        await drift(c)
        XCTAssertEqual(c.veilLevel(), 0)
        XCTAssertGreaterThan(c.edgeLevel(), 90)
    }

    func testTheEdgesOpenAgainWhenYouReturnAndStayOpenInPractice() async {
        let c = make { $0.screenEdges = true }
        await drift(c)
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        await advance(c, to: t + 60)
        XCTAssertEqual(c.edgeLevel(), 0, accuracy: 0.5)

        t = 0
        let practice = SessionController(judge: judge, store: DataStore(), prefs: { let p = noWords(); p.screenEdges = true; return p }(), now: { [unowned self] in self.t })
        practice.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        practice.begin(task: "Calc homework", preset: .standard, shadow: true)
        await drift(practice)
        XCTAssertEqual(practice.edgeLevel(), 0, "practice sessions never change the screen")
    }

    func testPreviewFadesUpAndBackLikeTheGrayDoes() {
        let c = SessionController(judge: judge, prefs: noWords(), now: { [unowned self] in self.t })
        XCTAssertEqual(c.edgeLevel(), 0)
        c.previewEdges()
        t = 5; XCTAssertEqual(c.edgeLevel(), 100)
        XCTAssertTrue(c.isPreviewingEdges); XCTAssertFalse(c.isPreviewingVeil, "the two previews are separate")
        t = 11; XCTAssertEqual(c.edgeLevel(), 0); XCTAssertFalse(c.isPreviewingEdges)
    }
}

final class LandingRulesTests: XCTestCase {
    func testOnlyATripThatArrivedGetsARing() {
        XCTAssertEqual(Landing.style(for: .exact), .exact)
        XCTAssertEqual(Landing.style(for: .appOnly), .approximate)
        XCTAssertEqual(Landing.style(for: .notFound), .none, "nothing came forward, so nothing is marked")
        XCTAssertEqual(Landing.style(for: .alreadyThere), .none)
    }

    func testTheRingIsShortAndHasNoMotionWithReduceMotion() {
        let calm = Landing.timeline(reduceMotion: false), still = Landing.timeline(reduceMotion: true)
        XCTAssertLessThanOrEqual(calm.fadeIn + calm.hold + calm.fadeOut, 2.0)
        XCTAssertEqual(still.fadeIn, 0); XCTAssertEqual(still.fadeOut, 0)
        XCTAssertGreaterThan(still.hold, 0.5)
    }

    func testAnApproximateRingIsLighterThanAnExactOne() {
        XCTAssertLessThan(Landing.opacity(.approximate), Landing.opacity(.exact))
        XCTAssertLessThan(Landing.width(.approximate), Landing.width(.exact))
    }

    @MainActor func testTheRingIsOnByDefaultAndCanBeSwitchedOff() {
        XCTAssertTrue(noWords().landingRing)
    }
}

@MainActor
final class LandingControllerTests: XCTestCase {
    var t = 0.0
    func make(front: String, frame: CGRect? = CGRect(x: 100, y: 120, width: 800, height: 600), configure: (Preferences) -> Void = { _ in }) -> (SessionController, LandingController) {
        let prefs = noWords(); configure(prefs)
        let c = SessionController(judge: CountingJudge { _ in Verdict(label: .onTask) }, store: DataStore(), prefs: prefs, now: { [unowned self] in self.t })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        c.frontAppName = { front }
        c.frontWindowFrame = { frame }
        return (c, LandingController(controller: c))
    }
    func report(_ app: String, _ o: ReturnOutcome) -> ReturnReport { ReturnReport(place: TaskPlace(window: WindowSnapshot(app: app, title: "x"), lastSeen: 0), outcome: o, at: 0) }
    func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    func testRingsTheWindowThatCameForward() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let (c, l) = make(front: "Pages")
        c.lastReturn = report("Pages", .exact)
        l.start(); l.returned()
        await wait(0.6)
        XCTAssertTrue(l.isShowing)
        let primaryH = NSScreen.screens[0].frame.height
        let f = try XCTUnwrap(l.frameForTesting)
        XCTAssertEqual(f.minX, 97, accuracy: 0.5); XCTAssertEqual(f.width, 806, accuracy: 0.5); XCTAssertEqual(f.height, 606, accuracy: 0.5)
        XCTAssertEqual(f.minY, primaryH - 120 - 600 - 3, accuracy: 0.5, "Core Graphics counts from the top, Cocoa from the bottom")
        l.stop()
        XCTAssertFalse(l.isShowing)
    }

    func testNothingIsRungWhenSwitchedOffOrNothingCameForward() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let (c, l) = make(front: "Pages", configure: { $0.landingRing = false })
        c.lastReturn = report("Pages", .exact)
        l.start(); l.returned(); await wait(0.5)
        XCTAssertFalse(l.isShowing, "switched off in Settings")
        l.stop()

        let (c2, l2) = make(front: "Pages")
        c2.lastReturn = report("Pages", .notFound)
        l2.start(); l2.returned(); await wait(0.5)
        XCTAssertFalse(l2.isShowing, "nothing was found, so nothing is marked")
        c2.lastReturn = report("Pages", .alreadyThere)
        l2.returned(); await wait(0.5)
        XCTAssertFalse(l2.isShowing)
        l2.stop()
    }

    func testItWaitsForThePlaceToBeInFrontAndNeverRingsTheWindowYouLeft() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        var front = "Slack"
        let (c, l) = make(front: "Slack")
        c.frontAppName = { front }
        c.lastReturn = report("Pages", .appOnly)
        l.start(); l.returned()
        await wait(0.45)
        XCTAssertFalse(l.isShowing, "Slack is still in front")
        front = "Pages"
        await wait(0.4)
        XCTAssertTrue(l.isShowing)
        l.stop()
    }
}
