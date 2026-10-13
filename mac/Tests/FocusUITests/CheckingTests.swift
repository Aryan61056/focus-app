import XCTest
import FocusBrain
import FocusJudge
@testable import FocusUI

final class SensitivityTests: XCTestCase {
    /// A judge that says off task with a given confidence, and "does not serve the task" as the second opinion.
    struct Unsure: Judge {
        var confidence: Int
        func reasonFirst(prompt: String) async -> Verdict { Verdict(label: .offTask, reason: "video", confidence: confidence) }
        func relation(prompt: String) async -> Verdict { Verdict(label: .offTask) }
    }
    let m = Moment(task: "Calc homework", app: "Safari", windowTitle: "clip youtube", url: "https://youtube.com/watch?v=1", documentPath: "", windowText: "", project: ProjectProfile())

    func testALowerBarFlagsWhatTheCarefulBarLeavesAlone() async {
        let j = Unsure(confidence: 70)
        let careful = await Pipeline.judge(m, with: j, useRules: false, minOffConfidence: Sensitivity.careful.minOffConfidence)
        let balanced = await Pipeline.judge(m, with: j, useRules: false, minOffConfidence: Sensitivity.balanced.minOffConfidence)
        let proactive = await Pipeline.judge(m, with: j, useRules: false, minOffConfidence: Sensitivity.proactive.minOffConfidence)
        XCTAssertEqual(careful.label, .unsure, "70 percent is not enough for the careful bar")
        XCTAssertEqual(balanced.label, .unsure, "nor for 80")
        XCTAssertEqual(proactive.label, .offTask, "but it is enough for the proactive bar")
    }

    func testEvenTheLowestBarStillLeavesAGuessAlone() async {
        let j = Unsure(confidence: 40)
        let r = await Pipeline.judge(m, with: j, useRules: false, minOffConfidence: Sensitivity.proactive.minOffConfidence)
        XCTAssertEqual(r.label, .unsure, "below 60 it is a guess, and a guess is never a warning")
    }

    func testTheBarsAreOrderedAndTheOldDefaultIsTheCarefulOne() {
        XCTAssertGreaterThan(Sensitivity.careful.minOffConfidence, Sensitivity.balanced.minOffConfidence)
        XCTAssertGreaterThan(Sensitivity.balanced.minOffConfidence, Sensitivity.proactive.minOffConfidence)
        XCTAssertEqual(Sensitivity.careful.minOffConfidence, Pipeline.minOffConfidence)
    }

    @MainActor func testShippedDefaultsAreProactiveAndOften() {
        let p = Preferences(defaults: UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!)
        XCTAssertEqual(p.sensitivity, .proactive); XCTAssertEqual(p.checkRate, .often)
        XCTAssertLessThan(CheckRate.often.scale, 1, "often means shorter intervals than the original timing")
        XCTAssertLessThan(CheckRate.veryOften.scale, CheckRate.often.scale)
        XCTAssertGreaterThan(CheckRate.rarely.scale, 1)
    }

    @MainActor func testChoicesAreRemembered() {
        let d = UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!
        let p = Preferences(defaults: d); p.sensitivity = .careful; p.checkRate = .rarely
        let q = Preferences(defaults: d)
        XCTAssertEqual(q.sensitivity, .careful); XCTAssertEqual(q.checkRate, .rarely)
    }
}

@MainActor
final class CheckRateTests: XCTestCase {
    var t = 0.0
    let judge = CountingJudge { p in Verdict(label: p.contains("youtube") ? .offTask : .onTask) }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }

    /// Seconds from the switch to a distraction until the brain warns, and how many judge calls it took on the way.
    func secondsToWarning(_ rate: CheckRate) async -> (seconds: Double, calls: Int) {
        t = 0
        let prefs = noWords(); prefs.checkRate = rate
        let j = CountingJudge { p in Verdict(label: p.contains("youtube") ? .offTask : .onTask) }
        let c = SessionController(judge: j, store: DataStore(), prefs: prefs, now: { [unowned self] in self.t })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 20)
        let start = t, before = j.calls
        c.windowChanged(WindowSnapshot(app: "Safari", title: "clip youtube", url: "https://youtube.com/watch?v=1"))
        while c.presence.state != "interrupted" && t < 400 { await advance(c, to: t + 1) }
        XCTAssertEqual(c.presence.state, "interrupted", "\(rate) never warned")
        return (t - start, j.calls - before)
    }

    func testCheckingMoreOftenWarnsSoonerAndAsksTheModelMore() async {
        let normal = await secondsToWarning(.normal), often = await secondsToWarning(.often), very = await secondsToWarning(.veryOften), rare = await secondsToWarning(.rarely)
        print("seconds to warning: rarely \(rare.seconds), normal \(normal.seconds), often \(often.seconds), very often \(very.seconds)")
        XCTAssertLessThan(often.seconds, normal.seconds)
        XCTAssertLessThan(very.seconds, often.seconds)
        XCTAssertLessThan(normal.seconds, rare.seconds)
    }

    func testAnOnTaskStretchIsCheckedMoreOftenToo() async {
        func calls(_ rate: CheckRate) async -> Int {
            t = 0
            let prefs = noWords(); prefs.checkRate = rate
            let j = CountingJudge { _ in Verdict(label: .onTask) }
            let c = SessionController(judge: j, store: DataStore(), prefs: prefs, now: { [unowned self] in self.t })
            c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
            c.begin(task: "Calc homework", preset: .standard, shadow: false)
            await advance(c, to: 300)
            return j.calls
        }
        let normal = await calls(.normal), often = await calls(.often)
        XCTAssertGreaterThan(often, normal, "same five minutes on task: more looks when set to often")
    }
}
