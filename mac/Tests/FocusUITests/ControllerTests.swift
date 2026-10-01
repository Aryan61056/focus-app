import XCTest
import FocusBrain
import FocusJudge
@testable import FocusUI

final class CountingJudge: Judge, @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    let verdict: @Sendable (String) -> Verdict
    init(_ verdict: @escaping @Sendable (String) -> Verdict) { self.verdict = verdict }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return n }
    func hit() { lock.lock(); n += 1; lock.unlock() }
    func reasonFirst(prompt: String) async -> Verdict { hit(); return verdict(prompt) }
    func relation(prompt: String) async -> Verdict { hit(); return verdict(prompt) }
}

@MainActor
final class ControllerTests: XCTestCase {
    var t = 0.0
    func make(_ judge: any Judge) -> SessionController { SessionController(judge: judge, now: { [unowned self] in self.t }) }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }
    let off = CountingJudge { p in Verdict(label: p.contains("youtube") ? .offTask : .onTask) }
    let editor = WindowSnapshot(app: "Notes", title: "Calc homework")
    let video = WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1")

    func testSessionStartsAtRestAndShowsOnTask() async {
        let c = make(off)
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 5)
        XCTAssertTrue(c.isActive)
        XCTAssertEqual(c.presence.state, "resting")
        XCTAssertEqual(c.presenceLabel, "On task")
        XCTAssertGreaterThanOrEqual(off.calls, 1)
    }

    func testSustainedDistractionNudgesOnceAndBackToTaskDismissesIt() async {
        let c = make(off)
        var brought: String?? = nil
        c.onBringBack = { brought = .some($0) }
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 20)
        c.windowChanged(video)
        await advance(c, to: 80)
        XCTAssertNil(c.surface, "too early: a distraction needs time and a second verdict")
        while c.surface == nil && t < 200 { await advance(c, to: t + 1) }   // the card fades after 12 s, so catch it when it appears
        XCTAssertEqual(c.presence.state, "interrupted")
        XCTAssertEqual(c.surface?.kind, "card")
        c.act(.backToTask)
        XCTAssertNil(c.surface)
        XCTAssertNotNil(brought)
        XCTAssertEqual(brought!, Keys.window(editor))
    }

    func testPracticeModeNeverShowsAnythingButCountsMoments() async {
        let c = make(off)
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: true)
        await advance(c, to: 20)
        c.windowChanged(video)
        await advance(c, to: 200)
        XCTAssertNil(c.surface)
        XCTAssertEqual(c.presence.state, "resting")
        XCTAssertGreaterThan(c.shadowMarks, 0)
    }

    func testSensitiveWindowIsNeverSentToTheJudge() async {
        let c = make(off)
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 10)
        let before = off.calls
        c.windowChanged(WindowSnapshot(app: "1Password", title: "Vault"))
        await advance(c, to: 120)
        XCTAssertEqual(c.presence, Presence(state: "paused", reason: "sensitive"))
        XCTAssertEqual(off.calls, before)
        c.windowChanged(editor)
        await advance(c, to: 125)
        XCTAssertEqual(c.presence.state, "resting")
    }

    func testRefusalNeverProducesANudge() async {
        let refusing = CountingJudge { p in Verdict(label: p.contains("youtube") ? .offTask : .onTask, error: p.contains("youtube") ? "guardrail" : nil) }
        let c = make(refusing)
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 20)
        c.windowChanged(video)
        await advance(c, to: 600)
        XCTAssertNil(c.surface)
        XCTAssertNotEqual(c.presence.state, "interrupted")
    }

    func testEndShowsSummaryAndStopsEverything() async {
        let c = make(off)
        c.windowChanged(editor)
        c.begin(task: "Calc homework")
        await advance(c, to: 60)
        c.end()
        XCTAssertFalse(c.isActive)
        XCTAssertEqual(c.presence.state, "off")
        XCTAssertEqual(c.summary?.activeSeconds ?? 0, 60, accuracy: 1)
    }

    func testKeysDropQueryAndSplitContentByText() {
        let a = WindowSnapshot(app: "Safari", title: "x", url: "https://Example.com/a/b?utm=1#frag", text: "one")
        let b = WindowSnapshot(app: "Safari", title: "x", url: "https://example.com/a/b?utm=2", text: "two")
        XCTAssertEqual(Keys.window(a), Keys.window(b))
        XCTAssertNotEqual(Keys.content(a), Keys.content(b))
        XCTAssertEqual(Keys.site(a), "safari|example.com")
        XCTAssertEqual(Keys.window(WindowSnapshot(app: "Notes", title: "  Calc   Homework ")), "notes|calc homework")
    }
}

@MainActor
final class ControllerStoreTests: XCTestCase {
    var t = 0.0
    let judge = CountingJudge { p in Verdict(label: p.contains("youtube") ? .offTask : .onTask) }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }
    let editor = WindowSnapshot(app: "Notes", title: "Calc homework")
    let video = WindowSnapshot(app: "Safari", title: "clip youtube", url: "https://youtube.com/watch?v=1")

    func testSessionIsRecordedWithTimelineThatAddsUp() async {
        let store = DataStore()
        let c = SessionController(judge: judge, store: store, now: { [unowned self] in self.t })
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 40)
        c.windowChanged(video); await advance(c, to: 110)
        c.windowChanged(editor); await advance(c, to: 180)
        c.end()
        let r = store.sessions.first!
        XCTAssertEqual(store.projects.map { $0.name }, ["Calc homework"])
        XCTAssertEqual(r.projectId, store.projects.first?.id)
        XCTAssertEqual(r.segments.reduce(0) { $0 + $1.seconds }, 180, accuracy: 1.5)
        XCTAssertTrue(r.segments.contains { $0.kind == .off })
        XCTAssertGreaterThan(r.drifts, 0)
    }

    func testThatWasFinePersistsASiteRuleForTheProjectAndTheNextSessionUsesIt() async {
        let store = DataStore()
        let c = SessionController(judge: judge, store: store, now: { [unowned self] in self.t })
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 10)
        c.windowChanged(video)
        while c.surface == nil && t < 300 { await advance(c, to: t + 1) }
        c.act(.markRelevant)
        c.end()
        XCTAssertEqual(store.projects.first?.profile.alwaysAllowDomains, ["youtube.com"])
        // next session: the same site is on task by rule, with no judge call
        let before = judge.calls
        t = 0
        let c2 = SessionController(judge: judge, store: store, now: { [unowned self] in self.t })
        c2.windowChanged(video)
        c2.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c2, to: 200)
        XCTAssertEqual(judge.calls, before)
        XCTAssertEqual(c2.presence.state, "resting")
    }

    func testPracticeModeQueuesMomentsForReview() async {
        let store = DataStore()
        let c = SessionController(judge: judge, store: store, now: { [unowned self] in self.t })
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: true)
        await advance(c, to: 20); c.windowChanged(video); await advance(c, to: 200)
        XCTAssertGreaterThan(store.openReviewCount, 0)
        XCTAssertEqual(store.review.first?.siteKey, "safari|youtube.com")
    }
}
