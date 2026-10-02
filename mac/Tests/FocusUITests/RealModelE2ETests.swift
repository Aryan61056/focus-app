import XCTest
@testable import FocusUI
@testable import FocusJudge
@testable import FocusBrain

/// Slow (about 35 s) and uses Apple's on-device model, so it only runs with FOCUS_E2E=1:
///   FOCUS_E2E=1 swift test --filter RealModelE2ETests
/// Scripted windows and a fake clock; nothing is read from the real screen. 2026-10-02: nudge 55 s after switching to a video site (Standard).
@MainActor
final class RealModelE2ETests: XCTestCase {
    func testASessionWithTheRealModelNudgesAfterSustainedDrift() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FOCUS_E2E"] == "1", "set FOCUS_E2E=1")
        guard DefaultJudge.status() == .ready else { throw XCTSkip("model unavailable") }
        var t = 0.0
        let c = SessionController(judge: DefaultJudge.make(), now: { t })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework: integration by parts"))
        c.begin(task: "Calc homework: integration by parts", preset: .standard, shadow: false)
        for _ in 0..<20 { t += 1; c.tick(); await c.waitForJudgments() }
        XCTAssertNil(c.surface, "no nudge while on task")
        c.windowChanged(WindowSnapshot(app: "Google Chrome", title: "Funniest cat videos 2026 - YouTube", url: "https://youtube.com/watch?v=abc"))
        let start = t
        while c.surface == nil && t < start + 600 { t += 1; c.tick(); await c.waitForJudgments() }
        XCTAssertNotNil(c.surface, "a nudge within ten minutes of a clear distraction")
        XCTAssertLessThan(t - start, 180)
    }
}
