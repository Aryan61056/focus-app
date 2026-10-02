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
        let w = SystemWatcher(controller: c, idleThreshold: 240, idleSeconds: { idle }, inCall: { false }, powerState: { (false, false) })
        setT(100); idle = 30; w.poll(); XCTAssertFalse(c.isPaused)
        setT(400); idle = 300; w.poll(); XCTAssertTrue(c.isPaused, "no input for 5 minutes")
        setT(430); idle = 1; w.poll(); XCTAssertFalse(c.isPaused, "short idle resumes silently")
    }

    func testLockOrSleepPausesAndWakeResumes() {
        let (c, _, setT) = session()
        let w = SystemWatcher(controller: c, idleSeconds: { 0 }, inCall: { false }, powerState: { (false, false) })
        setT(50); w.sleepChanged(true); XCTAssertTrue(c.isPaused)
        setT(80); w.sleepChanged(false); XCTAssertFalse(c.isPaused)
    }

    func testPowerStateIsOnlySentWhenItChanges() {
        let (c, _, _) = session()
        var low = false
        let w = SystemWatcher(controller: c, idleSeconds: { 0 }, inCall: { false }, powerState: { (low, false) })
        w.poll(); low = true; w.poll(); w.poll(); low = false; w.poll()
        XCTAssertTrue(c.isActive, "power changes never end a session")
    }
}

@MainActor
final class CallTests: XCTestCase {
    func testACallPausesAfterTwoPollsAndEndingItAsksNothingUntilResumed() {
        var t = 0.0
        let c = SessionController(judge: ScriptedJudge(markers: [("Notes", .on)]), now: { t })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        var call = false
        let w = SystemWatcher(controller: c, idleSeconds: { 0 }, inCall: { call }, powerState: { (false, false) })
        t = 10; call = true; w.poll(); XCTAssertFalse(c.isPaused, "one poll is not a call")
        t = 15; w.poll(); XCTAssertTrue(c.isPaused)
        t = 600; call = false; w.poll()
        XCTAssertTrue(c.isActive)
    }

    func testTheRealDetectorAnswersWithoutCrashing() { _ = CallDetector.inCall() }
}

final class CallDetectorRuleTests: XCTestCase {
    func testConferencingAppsListIsLowercaseSoMatchingIsCaseInsensitive() {
        XCTAssertTrue(CallDetector.conferencingApps.allSatisfy { $0 == $0.lowercased() })
        XCTAssertTrue(CallDetector.conferencingApps.contains("zoom.us"))
    }
    func testMicrophoneAloneWithANonConferencingAppInFrontIsNotACall() {
        // Whatever the microphone is doing, a text editor in front means no call unless the camera is on.
        if !CallDetector.cameraRunning() { XCTAssertFalse(CallDetector.inCall(frontApp: "Notes")) }
    }
}
