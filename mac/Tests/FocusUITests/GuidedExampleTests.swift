import XCTest
@testable import FocusUI

@MainActor final class GuidedExampleTests: XCTestCase {
    func testAllScenesUseTheRealControllerAndAnIsolatedStore() async {
        let example = GuidedExample()
        await example.waitUntilReady()
        XCTAssertEqual(example.controller.latest?.call, .on)
        XCTAssertFalse(example.controller.prefs.readScreen)
        example.select(1); await example.waitUntilReady()
        XCTAssertEqual(example.controller.latest?.call, .off)
        XCTAssertNil(example.controller.surface)
        example.select(2); await example.waitUntilReady()
        XCTAssertNotNil(example.controller.surface)
        example.select(3); await example.waitUntilReady()
        XCTAssertEqual(example.controller.latest?.call, .on)
        XCTAssertNil(example.controller.surface)
        XCTAssertEqual(example.controller.presence.state, "resting")
        example.select(0); await example.waitUntilReady()
        XCTAssertEqual(example.step, 0)
        example.stop(); XCTAssertFalse(example.controller.isActive)
    }
    func testImmediateStopCannotRestartFromAQueuedRender() async {
        let example = GuidedExample()
        example.stop()
        await example.waitUntilReady()
        XCTAssertFalse(example.controller.isActive)
    }
    func testRapidSelectionOnlyKeepsTheLastScene() async {
        let example = GuidedExample()
        example.select(2); example.select(3); example.select(1)
        await example.waitUntilReady()
        XCTAssertEqual(example.step, 1)
        XCTAssertNil(example.controller.surface)
        XCTAssertEqual(example.controller.latest?.call, .off)
        example.stop()
    }
    func testCannotOpenAnExampleOverARealSession() {
        let c = SessionController(judge: UnsureJudge(), store: DataStore())
        c.begin(task: "Synthetic task")
        c.showExample(); XCTAssertNil(c.example)
        c.end(); c.showExample(); XCTAssertNotNil(c.example)
        c.requestStart(); XCTAssertNil(c.example)
    }
}
