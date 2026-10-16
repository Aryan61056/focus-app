import XCTest
@testable import FocusBrain

final class TaskChangeTests: XCTestCase {
    func testTaskChangePreservesClockAndHoldsButClearsOldEvidence() {
        var b = Brain(); var config = SessionConfig(); config.mode = .timed; config.durationSeconds = 300
        _ = b.step(0, .sessionStart(config))
        _ = b.step(1, .windowChange(WindowChangeInput(windowKey: "work")))
        var j = JudgmentInput(requestId: 1, observedAt: 1, windowKey: "work", contentKey: "a", label: .offTask); j.strong = true
        _ = b.step(2, .judgment(j))
        _ = b.step(20, .userAction(.pause, minutes: nil))
        let fx = b.step(30, .taskChanged)
        XCTAssertTrue(b.isHeld); XCTAssertNil(b.window); XCTAssertNil(b.block)
        XCTAssertTrue(b.cache.isEmpty); XCTAssertNil(b.inFlight)
        XCTAssertFalse(fx.contains { if case .interrupt = $0 { return true }; return false })
        XCTAssertEqual(b.session?.duration, 300)
        let end = b.step(40, .sessionEnd)
        XCTAssertTrue(end.contains { if case .summary(let active, _, _, _, _, _) = $0 { return active == 20 }; return false })
    }
}
