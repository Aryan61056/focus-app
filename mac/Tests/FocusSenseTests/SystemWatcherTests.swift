import XCTest
@testable import FocusSense
@testable import FocusUI
@testable import FocusJudge
@testable import FocusBrain

@MainActor
final class SystemWatcherTests: XCTestCase {
    func session() -> (SessionController, () -> Double, (Double) -> Void) {
        var t = 0.0
        let c = SessionController(judge: ScriptedJudge(markers: [("Notes", .on)]), now: { t })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        return (c, { t }, { t = $0 })
    }

    func testLongIdlePausesTheClockAndInputResumesIt() {
        let (c, _, setT) = session()
        var idle = 0.0
        let w = SystemWatcher(controller: c, idleThreshold: 240, idleSeconds: { idle }, powerState: { (false, false) })
        setT(100); idle = 30; w.poll(); XCTAssertFalse(c.isPaused)
        setT(400); idle = 300; w.poll(); XCTAssertTrue(c.isPaused, "no input for 5 minutes")
        setT(430); idle = 1; w.poll(); XCTAssertFalse(c.isPaused, "short idle resumes silently")
    }

    func testLockOrSleepPausesAndWakeResumes() {
        let (c, _, setT) = session()
        let w = SystemWatcher(controller: c, idleSeconds: { 0 }, powerState: { (false, false) })
        setT(50); w.sleepChanged(true); XCTAssertTrue(c.isPaused)
        setT(80); w.sleepChanged(false); XCTAssertFalse(c.isPaused)
    }

    func testPowerStateIsOnlySentWhenItChanges() {
        let (c, _, _) = session()
        var low = false
        let w = SystemWatcher(controller: c, idleSeconds: { 0 }, powerState: { (low, false) })
        w.poll(); low = true; w.poll(); w.poll(); low = false; w.poll()
        XCTAssertTrue(c.isActive, "power changes never end a session")
    }
}
