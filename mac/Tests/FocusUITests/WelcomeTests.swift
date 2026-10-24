import XCTest
@testable import FocusUI
import FocusJudge

/// The welcome (2026-10-16): once on a new Mac, never in someone's way after that, and its last step really starts a session.
@MainActor
final class WelcomeTests: XCTestCase {
    var t = 0.0
    func make(_ defaults: UserDefaults? = nil) -> SessionController {
        let prefs = Preferences(defaults: defaults ?? UserDefaults(suiteName: "focus.welcome.\(UUID().uuidString)")!)
        return SessionController(judge: CountingJudge { _ in Verdict(label: .onTask) }, store: DataStore(), prefs: prefs, now: { [unowned self] in self.t })
    }

    func testANewMacOpensOnTheWelcome() {
        XCTAssertTrue(make().showsWelcome)
    }

    func testSomeoneWhoAlreadyUsedFocusNeverGetsItUnasked() async {
        let seen = make(); seen.prefs.introSeen = true
        XCTAssertFalse(seen.showsWelcome, "the old first-run intro was seen")
        let used = make()
        used.finishWelcome(explained: false); used.prefs.welcomeSeen = false   // as if it never ran, but with a session saved
        used.begin(task: "Calc homework"); t = 30; used.end()
        XCTAssertFalse(used.store!.sessions.isEmpty)
        XCTAssertFalse(used.showsWelcome, "sessions are saved")
        let noStore = SessionController(judge: CountingJudge { _ in Verdict(label: .onTask) }, now: { 0 })
        XCTAssertFalse(noStore.showsWelcome, "nothing to start a first session in")
    }

    func testNeverDuringASession() {
        let c = make()
        c.begin(task: "Calc homework")
        XCTAssertFalse(c.showsWelcome)
        c.welcomeRequested = true
        XCTAssertFalse(c.showsWelcome, "not even when asked for from Settings")
    }

    func testSkippingEndsItButKeepsTodaysIntroAndFinishingMarksBoth() {
        let skipped = make()
        skipped.finishWelcome(explained: false)
        XCTAssertFalse(skipped.showsWelcome)
        XCTAssertFalse(skipped.prefs.introSeen, "skipped: Today still says how Hushd works")
        let done = make()
        done.finishWelcome(explained: true)
        XCTAssertFalse(done.showsWelcome)
        XCTAssertTrue(done.prefs.introSeen, "the welcome said it already")
    }

    func testItIsRememberedAcrossLaunches() {
        let defaults = UserDefaults(suiteName: "focus.welcome.\(UUID().uuidString)")!
        make(defaults).finishWelcome(explained: false)
        XCTAssertFalse(make(defaults).showsWelcome)
    }

    func testSettingsCanShowItAgain() {
        let c = make()
        c.finishWelcome(explained: true)
        c.welcomeRequested = true
        XCTAssertTrue(c.showsWelcome)
        c.finishWelcome(explained: true)
        XCTAssertFalse(c.showsWelcome, "and it goes away again")
    }

    func testTheLastStepStartsTheSessionYouTyped() {
        let timed = make()
        XCTAssertTrue(WelcomeView.start(timed, text: "Essay 25", autoTick: false))
        XCTAssertTrue(timed.isActive)
        XCTAssertEqual(timed.taskName, "Essay")
        XCTAssertEqual(timed.mode, .timed)
        XCTAssertFalse(timed.showsWelcome)
        let open = make()
        XCTAssertTrue(WelcomeView.start(open, text: "Lab report on pendulums", autoTick: false))
        XCTAssertEqual(open.mode, .open)
        let empty = make()
        XCTAssertFalse(WelcomeView.start(empty, text: "   ", autoTick: false))
        XCTAssertFalse(empty.isActive)
        XCTAssertTrue(empty.showsWelcome, "nothing typed, nothing started, still welcoming")
    }
}
