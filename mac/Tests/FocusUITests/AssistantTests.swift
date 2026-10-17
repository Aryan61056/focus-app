import XCTest
import FocusBrain
import FocusJudge
@testable import FocusUI

/// Records what the assistant was given, so the tests can check what the model is allowed to see.
final class SpyAssistant: Assistant, @unchecked Sendable {
    var recapFacts = "", answerFacts = "", sharpenInput = ""
    var recapOut: Recap? = Recap(summary: "You stayed with it for most of the session.")
    func sharpen(task: String, context: String) async -> Sharpened? { sharpenInput = task; return Sharpened(task: "Calculus homework, chapter 3", counts: "Textbook pages and worked examples.") }
    func recap(facts: String) async -> Recap? { recapFacts = facts; return recapOut }
    func answer(question: String, facts: String) async -> String? { answerFacts = facts; return "You were on a video page at 10:02." }
}

@MainActor
final class AssistantTests: XCTestCase {
    var t = 0.0
    let judge = ScriptedJudge(readings: [("youtube", .off, "A video unrelated to the task."), ("Notes", .on, "Your notes.")])
    func make(store: DataStore? = nil) -> (SessionController, SpyAssistant) {
        let store = store ?? DataStore()
        let c = SessionController(judge: judge, store: store, prefs: noWords(), now: { [unowned self] in self.t })
        let spy = SpyAssistant(); c.assistant = spy
        return (c, spy)
    }
    func settle(_ c: SessionController) async { for _ in 0..<20 { await Task.yield(); try? await Task.sleep(nanoseconds: 5_000_000) } }

    func testRecapRunsAfterTheSessionAndNamesNoWindows() async {
        let (c, spy) = make()
        c.windowChanged(WindowSnapshot(app: "Browser", title: "youtube clip secret-title", url: "https://youtube.com"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        while t < 5 { t += 1; c.tick(); await c.waitForJudgments() }
        c.end(); await settle(c)
        XCTAssertEqual(c.recap.value?.summary, "You stayed with it for most of the session.")
        XCTAssertFalse(spy.recapFacts.contains("secret-title"), "the recap sees counts, not window titles")
        XCTAssertFalse(spy.recapFacts.lowercased().contains("youtube"))
    }

    func testAskFocusMayUseWindowsBecauseTheUserAsked() async {
        let (c, spy) = make()
        c.windowChanged(WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        while t < 5 { t += 1; c.tick(); await c.waitForJudgments() }
        c.askFocus("What pulled me away?"); await settle(c)
        XCTAssertEqual(c.answer.value, "You were on a video page at 10:02.")
        XCTAssertTrue(spy.answerFacts.contains("youtube clip"))
    }

    func testTurningAIHelpOffMeansNothingIsAsked() async {
        let (c, spy) = make()
        c.prefs.aiHelp = false
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        c.askFocus("anything"); c.sharpenTask("calc"); c.end(); await settle(c)
        XCTAssertEqual(c.answer, .idle); XCTAssertEqual(c.sharpened, .idle); XCTAssertEqual(c.recap, .idle)
        XCTAssertEqual(spy.answerFacts + spy.recapFacts + spy.sharpenInput, "")
    }

    func testModelFailureShowsNothingAndNeverCrashes() async {
        let (c, spy) = make(); spy.recapOut = nil
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false); c.end(); await settle(c)
        XCTAssertEqual(c.recap, .failed)
    }

    func testAcceptedCoachContextFillsAnEmptyProjectOnly() {
        let store = DataStore()
        let (c, _) = make(store: store)
        c.saveContextIfEmpty(task: "Essay", context: "Sources and drafts.")
        XCTAssertEqual(store.projectNamed("Essay").context, "Sources and drafts.")
        c.saveContextIfEmpty(task: "Essay", context: "Something else.")
        XCTAssertEqual(store.projectNamed("Essay").context, "Sources and drafts.", "a description the user wrote is never replaced")
    }

    func testSharpenReturnsASuggestionAndChangesNothing() async {
        let store = DataStore()
        let (c, _) = make(store: store)
        c.sharpenTask("calc homework"); await settle(c)
        XCTAssertEqual(c.sharpened.value?.task, "Calculus homework, chapter 3")
        XCTAssertTrue(store.projects.isEmpty)
    }

    func testJudgingFlagTurnsOnAndOff() async {
        let (c, _) = make()
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await c.waitForJudgments()
        XCTAssertFalse(c.isJudging)
    }
}

@MainActor
final class PracticeRemovedTests: XCTestCase {
    func testRemovedPracticeNeverWatchesOnlyAndCannotComeBackByAccident() {
        let c = SessionController(judge: ScriptedJudge(markers: []), prefs: noWords())
        XCTAssertTrue(c.prefs.practiceActive, "default: practice on for a new user")
        c.prefs.practiceRemoved = true
        XCTAssertFalse(c.prefs.practiceActive)
        c.prefs.restartPractice()
        XCTAssertFalse(c.prefs.practiceActive, "restart does nothing while removed")
        c.begin(task: "Essay")
        XCTAssertFalse(c.shadow, "a removed practice mode means real nudges from the first session")
        c.begin(task: "x", shadow: true)   // already active, ignored
        XCTAssertFalse(c.showsReview, "Review is hidden when practice is removed and nothing is waiting")
    }

    func testRemovalIsRememberedAndReversible() {
        let d = UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!
        let p = Preferences(defaults: d); p.practiceRemoved = true
        XCTAssertTrue(Preferences(defaults: d).practiceRemoved)
        XCTAssertFalse(Preferences(defaults: d).practiceActive)
        p.practiceRemoved = false; p.restartPractice()
        XCTAssertTrue(Preferences(defaults: d).practiceActive)
    }
}
