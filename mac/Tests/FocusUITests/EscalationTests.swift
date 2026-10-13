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
        XCTAssertTrue(c.escalationGate, "then the pause screen"); XCTAssertEqual(c.shield?.kind, .pause)
        XCTAssertNil(c.checkIn)
        XCTAssertEqual(foreground, 0, "the pause screen is its own panel now, not the Focus window coming forward")
        XCTAssertTrue(hidden.isEmpty)

        await advance(c, to: warned + 201)
        XCTAssertEqual(hidden, ["Safari"], "then the app you drifted into is hidden")
        await advance(c, to: warned + 201 + 120)
        XCTAssertEqual(hidden, ["Safari", "Safari"], "and again every two minutes while you stay away")
    }

    func testExplainingNeedsTheHoldButNoWaitAndBackToTaskIsAlwaysThere() async {
        let c = make()
        let warned = await driftUntilWarned(c)
        await advance(c, to: warned + 101)
        XCTAssertTrue(c.gateOpen)
        XCTAssertEqual(c.shield?.kind, .pause)
        XCTAssertEqual(c.shieldWaitRemaining(), 0, "no wait before explaining")
        c.leaveGate(fine: true)
        XCTAssertEqual(c.shield?.asking, false, "the old one-click That was fine does not open the form")
        c.beginShieldHold(); t += 5.1; c.updateShieldHold()
        XCTAssertEqual(c.shield?.asking, true, "the hold alone opens the form")
        c.leaveGate(fine: false)
        XCTAssertFalse(c.gateOpen, "Back to task is always available")
        XCTAssertNil(c.shield)
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

    func testAnsweringYesToTheCheckInNowHasToBeExplainedNotJustClicked() async {
        let c = make()
        let warned = await driftUntilWarned(c)
        await advance(c, to: warned + 41)
        XCTAssertNotNil(c.checkIn)
        c.answerCheckIn(onTask: true)
        XCTAssertNil(c.checkIn)
        XCTAssertEqual(c.shield?.kind, .claim, "a flagged window needs an explanation Focus can check")
        XCTAssertTrue(c.learnedRules.isEmpty, "nothing was learned from a click")
        XCTAssertEqual(c.presence.state, "interrupted")
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

@MainActor
final class TabEnforcementTests: XCTestCase {
    let on = WindowSnapshot(app: "Safari", title: "Calc homework", url: "https://docs.example.com/calc")
    let video = WindowSnapshot(app: "Safari", title: "clip youtube", url: "https://youtube.com/watch?v=1&t=9")
    var t = 0.0
    let judge = CountingJudge { p in Verdict(label: p.contains("youtube") ? .offTask : .onTask) }
    var switched: [(String, String?)] = [], closed: [String] = [], hidden: [String] = []

    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }
    func make(preset: Preset, _ configure: (SessionController) -> Void = { _ in }) -> SessionController {
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { [unowned self] in self.t })
        c.onSwitchTab = { [unowned self] from, to in switched.append((from.url, to?.url)); return true }
        c.onCloseTab = { [unowned self] w in closed.append(w.url); return true }
        c.onHideApp = { [unowned self] in hidden.append($0) }
        configure(c)
        c.windowChanged(on)
        c.begin(task: "Calc homework", preset: preset, shadow: false)
        return c
    }
    func warned(_ c: SessionController) async -> Double {
        await advance(c, to: 20)
        c.windowChanged(video)
        while c.presence.state != "interrupted" && t < 300 { await advance(c, to: t + 1) }
        XCTAssertEqual(c.presence.state, "interrupted")
        return t
    }

    func testPureChoice() {
        XCTAssertEqual(Enforcement.action(performed: 0, preset: .strict, switching: true, closing: true), .switchAway)
        XCTAssertEqual(Enforcement.action(performed: 0, preset: .strict, switching: false, closing: true), .hide, "no switching asked for: the first round hides as before")
        XCTAssertEqual(Enforcement.action(performed: 1, preset: .strict, switching: true, closing: true), .close)
        XCTAssertEqual(Enforcement.action(performed: 1, preset: .standard, switching: true, closing: true), .hide, "only Strict closes")
        XCTAssertEqual(Enforcement.action(performed: 3, preset: .strict, switching: true, closing: false), .hide)
    }

    func testOnlyNamedBrowserTabsMayBeClosed() {
        XCTAssertTrue(Enforcement.mayClose(video, neverJudged: [], skipPersonal: true))
        XCTAssertFalse(Enforcement.mayClose(WindowSnapshot(app: "Notes", title: "x", url: "https://youtube.com/a"), neverJudged: [], skipPersonal: true), "other apps are hidden, never closed")
        XCTAssertFalse(Enforcement.mayClose(WindowSnapshot(app: "Safari", title: "new tab"), neverJudged: [], skipPersonal: true), "no address: Focus cannot name the tab")
        XCTAssertFalse(Enforcement.mayClose(WindowSnapshot(app: "Finder", title: "x", url: "https://a.b/c"), neverJudged: [], skipPersonal: true))
        XCTAssertFalse(Enforcement.mayClose(nil, neverJudged: [], skipPersonal: true))
    }

    func testStandardSwitchesBackFirstThenHides() async {
        let c = make(preset: .standard)
        let w = await warned(c)
        await advance(c, to: w + 201)
        XCTAssertEqual(switched.count, 1)
        XCTAssertEqual(switched.first?.1, on.url, "it goes back to the tab you were working in")
        XCTAssertTrue(hidden.isEmpty, "a switch that worked is enough")
        await advance(c, to: w + 201 + 120)
        XCTAssertTrue(closed.isEmpty, "Standard never closes")
        XCTAssertEqual(hidden, ["Safari"], "later rounds hide")
    }

    func testStrictSwitchesThenCloses() async {
        let c = make(preset: .strict)
        let w = await warned(c)
        await advance(c, to: w + 121)
        XCTAssertEqual(switched.count, 1); XCTAssertTrue(closed.isEmpty)
        XCTAssertTrue(c.closeIsNext, "the banner says so before closing")
        await advance(c, to: w + 121 + 60)
        XCTAssertEqual(closed, [video.url], "the second round closes that tab")
        XCTAssertTrue(hidden.isEmpty)
        XCTAssertEqual(c.lastEnforce?.action, .close)
    }

    func testClosingCanBeSwitchedOff() async {
        let c = make(preset: .strict) { $0.prefs.closeOnStrict = false }
        let w = await warned(c)
        await advance(c, to: w + 121 + 60)
        XCTAssertTrue(closed.isEmpty); XCTAssertFalse(c.closeIsNext)
        XCTAssertEqual(hidden, ["Safari"])
    }

    func testFailedSwitchOrNoOnTaskTabFallsBackToHiding() async {
        let c = make(preset: .standard) { $0.onSwitchTab = { [unowned self] _, _ in switched.append(("", nil)); return false } }
        let w = await warned(c)
        await advance(c, to: w + 201)
        XCTAssertEqual(hidden, ["Safari"], "when the tab could not be switched, the app is hidden as before")
        XCTAssertEqual(c.lastEnforce?.done, false)
    }

    func testChromeAddressScriptAsksTheFrontTabAndHidesPrivateWindows() throws {
        let s = try XCTUnwrap(TabScript.currentURL(app: "Google Chrome"))
        XCTAssertTrue(s.contains("URL of active tab of front window") && s.contains("incognito"))
        XCTAssertNil(TabScript.currentURL(app: "Safari"), "Safari reports its address through Accessibility")
        XCTAssertNil(TabScript.currentURL(app: "Arc"))
    }

    func testSwitchingCanBeSwitchedOff() async {
        let c = make(preset: .standard) { $0.prefs.switchTabs = false }
        let w = await warned(c)
        await advance(c, to: w + 201)
        XCTAssertTrue(switched.isEmpty); XCTAssertEqual(hidden, ["Safari"])
    }

    func testScriptsEscapeTheAddress() throws {
        let s = try XCTUnwrap(TabScript.close(app: "Google Chrome", url: "https://a.com/x\"; do shell script \"rm -rf ~\"?q=1#f"))
        XCTAssertTrue(s.contains("active tab of front window"))
        XCTAssertTrue(s.contains("a.com/x\\\"; do shell script \\\"rm -rf ~\\\""), "every quote in the address is escaped, so it stays data")
        XCTAssertFalse(s.contains("q=1"), "query and fragment are dropped")
        XCTAssertNil(TabScript.close(app: "Arc", url: "https://a.com"))
        XCTAssertNil(TabScript.switchTo(app: "Safari", url: ""))
        XCTAssertTrue(try XCTUnwrap(TabScript.switchTo(app: "Safari", url: "docs.example.com/calc")).contains("set current tab of w to t"))
    }

    /// Compiles only (nothing runs, no permission needed), so a typo in the script text shows up here and not on the user's Mac.
    func testCometScriptsCompile() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/Applications/Comet.app"), "Comet not installed")
        for src in [TabScript.switchTo(app: "Comet", url: "https://docs.example.com/calc"), TabScript.close(app: "Comet", url: "https://youtube.com/watch"), TabScript.currentURL(app: "Comet")] {
            var err: NSDictionary?
            XCTAssertTrue(NSAppleScript(source: try XCTUnwrap(src))!.compileAndReturnError(&err), "\(String(describing: err))")
        }
        XCTAssertTrue(Enforcement.isBrowser("Comet"))
    }

    func testSafariScriptsCompile() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/Applications/Safari.app") || FileManager.default.fileExists(atPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"), "Safari not found")
        for src in [TabScript.switchTo(app: "Safari", url: "https://docs.example.com/calc?x=1"), TabScript.close(app: "Safari", url: "https://youtube.com/watch")] {
            var err: NSDictionary?
            XCTAssertTrue(NSAppleScript(source: try XCTUnwrap(src))!.compileAndReturnError(&err), "\(String(describing: err))")
        }
    }
}
