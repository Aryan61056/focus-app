import XCTest
import FocusBrain
import FocusJudge
@testable import FocusUI

@MainActor
final class ReadingTests: XCTestCase {
    var t = 0.0
    let judge = ScriptedJudge(readings: [
        ("youtube", .off, "A video unrelated to the task."),
        ("Notes", .on, "Your notes for the task."),
    ])
    let editor = WindowSnapshot(app: "Notes", title: "Calc homework")
    let video = WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1")

    func make(store: DataStore? = nil) -> SessionController { SessionController(judge: judge, store: store, now: { [unowned self] in self.t }) }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }

    func testLatestReadingCarriesTheModelsReasonAndCall() async {
        let c = make()
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 5)
        XCTAssertEqual(c.latest?.call, .on)
        XCTAssertEqual(c.latest?.source, .model)
        XCTAssertEqual(c.latest?.reason, "Your notes for the task.")
        XCTAssertEqual(c.latest?.app, "Notes")
    }

    func testRepeatChecksOfTheSameWindowDoNotRepeatTheLine() async {
        let c = make()
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 120)
        XCTAssertEqual(c.readings.count, 1)
        XCTAssertGreaterThan(c.stats.model, 1, "stats still count every check")
    }

    func testProjectRuleSettlesAWindowAndIsShownAsYourRule() async {
        let store = DataStore()
        var p = store.addProject(name: "Calc homework")
        p.profile.alwaysAllowApps = ["Notes"]
        store.update(p)
        let c = make(store: store)
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        XCTAssertEqual(c.latest?.source, .rule)
        XCTAssertEqual(c.latest?.call, .on)
        XCTAssertTrue(c.latest?.reason.hasPrefix("You told Focus") ?? false)
        XCTAssertEqual(c.stats.rule, 1)
    }

    func testSensitiveWindowShowsNoAppNoTitleAndNoModelCall() async {
        let c = make()
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        c.windowChanged(WindowSnapshot(app: "1Password", title: "Vault"))
        await advance(c, to: 3)
        XCTAssertEqual(c.latest?.source, .sensitive)
        XCTAssertEqual(c.latest?.app, "")
        XCTAssertEqual(c.latest?.title, "")
        XCTAssertEqual(c.latest?.appText, "Private window")
    }

    func testRefusalShowsAPlainLineNotTheRawError() async {
        let refusing = CountingJudge { _ in Verdict(label: .unsure, reason: "I can't help with that request", error: "guardrail") }
        let c = SessionController(judge: refusing, now: { [unowned self] in self.t })
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 5)
        XCTAssertEqual(c.latest?.failed, true)
        XCTAssertEqual(c.latest?.call, .unsure)
        XCTAssertEqual(c.latest?.reason, "Focus could not read this one, so it did nothing.")
    }

    func testStatsAreSavedWithTheSessionAndHoldNoText() async {
        let store = DataStore()
        let c = make(store: store)
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 30); c.end()
        let reads = store.sessions.first?.reads
        XCTAssertNotNil(reads)
        XCTAssertGreaterThan(reads?.onTask ?? 0, 0)
        let json = String(data: store.exportJSON() ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("Your notes for the task"), "readings and their reasons must not be written to disk")
        XCTAssertFalse(json.contains("youtube clip"))
    }

    func testReviewMomentKeepsTheReasonUntilAnsweredThenDropsIt() async {
        let store = DataStore()
        let c = make(store: store)
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: true)
        await advance(c, to: 20); c.windowChanged(video); await advance(c, to: 200)
        let m = try! XCTUnwrap(store.review.first)
        XCTAssertEqual(m.reason, "A video unrelated to the task.")
        store.answerReview(m.id, "right")
        XCTAssertNil(store.review.first?.reason)
        XCTAssertEqual(store.agreement.agreed, 1)
        XCTAssertEqual(store.agreement.answered, 1)
    }

    func testWhatYouWriteAboutAProjectReachesTheJudge() async {
        let seen = PromptBox()
        let spy = CountingJudge { p in seen.set(p); return Verdict(label: .onTask, reason: "ok") }
        let store = DataStore()
        var p = store.addProject(name: "Calc homework")
        p.context = "Integration by parts, chapter 5."
        store.update(p)
        let c = SessionController(judge: spy, store: store, now: { [unowned self] in self.t })
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 3)
        XCTAssertTrue(seen.value.contains("Integration by parts, chapter 5."), "Project.context must be in the judge prompt")
    }

    func testAskFocusRunsTheSameJudgeOnTypedText() async {
        let c = make()
        let p = Project(name: "Calc homework")
        let j = await c.ask(app: "Browser", title: "youtube clip", project: p)
        XCTAssertEqual(j.label, .offTask)
        XCTAssertNil(c.latest, "asking must not touch the live session")
    }
}

final class PromptBox: @unchecked Sendable {
    private let lock = NSLock(); private var s = ""
    func set(_ v: String) { lock.lock(); s = v; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return s }
}
