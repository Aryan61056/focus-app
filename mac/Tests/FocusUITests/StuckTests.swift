import XCTest
import FocusJudge
@testable import FocusUI

private actor NextActionSpy: Assistant {
    var received: [(String, String)] = []
    func sharpen(task: String, context: String) async -> Sharpened? { nil }
    func recap(facts: String) async -> Recap? { nil }
    func answer(question: String, facts: String) async -> String? { nil }
    func nextActions(task: String, context: String) async -> [String]? {
        received.append((task, context)); return ["Write one calculus example", "Ask the school about recycling"]
    }
    func inputs() -> [(String,String)] { received }
}

private struct SlowNextActions: Assistant {
    func sharpen(task: String, context: String) async -> Sharpened? { nil }
    func recap(facts: String) async -> Recap? { nil }
    func answer(question: String, facts: String) async -> String? { nil }
    func nextActions(task: String, context: String) async -> [String]? {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return ["Write one calculus example"]
    }
}

@MainActor final class StuckTests: XCTestCase {
    func testOnlyTaskAndProjectContextReachTheModelAndAcceptanceKeepsTheSession() async {
        var t = 0.0
        let store = DataStore(); var project = store.addProject(name: "Calculus"); project.context = "Integration by parts"; store.update(project)
        let c = SessionController(judge: UnsureJudge(), store: store, now: { t })
        let spy = NextActionSpy(); c.assistant = spy
        c.begin(task: "Calculus", projectId: project.id)
        c.windowChanged(WindowSnapshot(app: "Synthetic app", title: "DO NOT SEND TITLE", text: "DO NOT SEND OCR"))
        t = 20; c.tick(); c.requestNextActions(); await c.waitForNextActions()
        let inputs = await spy.inputs()
        XCTAssertEqual(inputs.count, 1); XCTAssertEqual(inputs[0].0, "Calculus"); XCTAssertEqual(inputs[0].1, project.context)
        XCTAssertEqual(c.nextActions.value, ["Write one calculus example"])
        c.chooseNextAction("Write one calculus example")
        XCTAssertEqual(c.taskName, "Write one calculus example"); XCTAssertTrue(c.isActive)
        XCTAssertEqual(c.projectId, project.id); XCTAssertFalse(c.stuckShown)
        t = 25; c.end(); XCTAssertEqual(c.summary?.activeSeconds, 25)
    }
    func testUnavailableAssistantHasACalmFallbackAndNoGoalChange() async {
        let c = SessionController(judge: UnsureJudge(), store: DataStore()); c.assistant = NoAssistant()
        c.begin(task: "Calculus"); c.requestNextActions(); await c.waitForNextActions()
        XCTAssertEqual(c.nextActions, .failed); XCTAssertEqual(c.taskName, "Calculus")
        c.chooseNextAction("Invented action"); XCTAssertEqual(c.taskName, "Calculus")
        c.cancelNextActions(); XCTAssertFalse(c.stuckShown)
    }
    func testSlowResponseFallsBackAndCannotArriveAfterTimeout() async throws {
        let c = SessionController(judge: UnsureJudge(), store: DataStore()); c.assistant = SlowNextActions()
        c.begin(task: "Calculus"); c.requestNextActions(timeoutNanoseconds: 1_000_000)
        try await Task.sleep(nanoseconds: 30_000_000)
        await c.waitForNextActions()
        XCTAssertEqual(c.nextActions, .failed); XCTAssertEqual(c.taskName, "Calculus")
        c.end(); XCTAssertFalse(c.stuckShown)
    }
    func testUnrelatedExampleLeakageAndDuplicatesAreFiltered() {
        XCTAssertEqual(NextActionFilter.actions(["Write a Spanish sentence about the trip", "Write a Spanish sentence about the trip", "Ask the school about recycling"], task: "Practice Spanish", context: "Yesterday's trip"), ["Write a Spanish sentence about the trip"])
    }
}
