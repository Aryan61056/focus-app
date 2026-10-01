import XCTest
@testable import FocusBrain
import BrainTraces

final class GoldenTraceTests: XCTestCase {
    func testAllGoldenTraces() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("core/traces")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        XCTAssertGreaterThanOrEqual(files.count, 16)
        for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let r = try TraceRunner.run(file: f)
            XCTAssertTrue(r.failures.isEmpty, "\(r.name): \(r.failures.prefix(3).joined(separator: "\n"))")
        }
    }
}

/// Small driver so scenario tests read like the spec.
struct Driver {
    var brain = Brain()
    var log: [(t: Double, fx: [Effect])] = []
    mutating func go(_ t: Double, _ e: Event) -> [Effect] { let fx = brain.step(t, e); log.append((t, fx)); return fx }
    mutating func start(_ preset: Preset = .standard, shadow: Bool = false) {
        var c = SessionConfig(); c.preset = preset; c.shadow = shadow
        _ = go(0, .sessionStart(c))
    }
    mutating func window(_ t: Double, _ key: String, site: String? = nil, rule: JudgmentLabel? = nil) -> [Effect] {
        go(t, .windowChange(WindowChangeInput(windowKey: key, siteKey: site, ruleLabel: rule)))
    }
    mutating func judge(_ t: Double, observed: Double? = nil, _ key: String, _ label: JudgmentLabel, strong: Bool = false, content: String = "c", flag: JudgmentFlag = .none) -> [Effect] {
        var j = JudgmentInput(observedAt: observed ?? t - 3.5, windowKey: key, contentKey: content, label: label)
        j.strong = strong; j.flag = flag
        return go(t, .judgment(j))
    }
    mutating func ticks(_ from: Double, _ to: Double) -> [(Double, [Effect])] {
        var out: [(Double, [Effect])] = []
        var t = from
        while t <= to { let fx = go(t, .tick); if !fx.isEmpty { out.append((t, fx)) }; t += 1 }
        return out
    }
    static func requests(_ fx: [Effect]) -> [(id: Int, allowVision: Bool)] {
        fx.compactMap { if case .requestJudgment(let id, _, _, _, let av) = $0 { return (id, av) } else { return nil } }
    }
}

final class BrainScenarioTests: XCTestCase {
    func testPowerConstrainedDoublesIntervalsAndDisablesVision() {
        var d = Driver(); d.start()
        _ = d.go(0, .powerChange(constrained: true, critical: false))
        _ = d.window(0, "w:e")
        _ = d.judge(3.5, observed: 0, "w:e", .onTask)
        let hits = d.ticks(4, 80).flatMap { Driver.requests($0.1) }
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.allowVision, false)
        let at = d.log.first { !Driver.requests($0.fx).isEmpty && $0.t > 4 }?.t
        XCTAssertEqual(at, 64)  // 3.5 + 2 x 30 = 63.5, first tick after
    }

    func testCriticalPowerStopsCadenceButNotWindowChanges() {
        var d = Driver(); d.start()
        _ = d.go(0, .powerChange(constrained: true, critical: true))
        _ = d.window(0, "w:e")
        _ = d.judge(3.5, observed: 0, "w:e", .onTask)
        XCTAssertTrue(d.ticks(4, 400).flatMap { Driver.requests($0.1) }.isEmpty)
        XCTAssertFalse(Driver.requests(d.window(401, "w:other")).isEmpty)
    }

    func testShortSleepResumesSilentlyLongSleepAsks() {
        var d = Driver(); d.start()
        _ = d.window(0, "w:e"); _ = d.judge(3.5, observed: 0, "w:e", .onTask)
        XCTAssertEqual(d.go(100, .sleep).first, .beacon(state: "paused", reason: "sleep"))
        XCTAssertTrue(d.go(150, .wake).contains(.beacon(state: "resting", reason: nil)))
        _ = d.go(200, .sleep)
        XCTAssertEqual(d.go(900, .wake), [.askResume(reason: "sleep")])
    }

    func testIgnoreWindowIsSessionScopedAndWins() {
        var d = Driver(); d.start()
        _ = d.window(0, "w:yt")
        for k in 0..<4 { _ = d.judge(3.5 + 14 * Double(k), observed: 14 * Double(k), "w:yt", .offTask, strong: true, content: "c\(k)") }
        let fx = d.go(60, .userAction(.ignoreWindow, minutes: nil))
        XCTAssertTrue(fx.contains(.learnRule(scope: "session", kind: "ignore", keyType: "window", key: "w:yt")))
        XCTAssertEqual(d.brain.focus, .onTask)
        XCTAssertNil(d.brain.block)
        XCTAssertTrue(d.judge(64, observed: 60.5, "w:yt", .offTask, strong: true).isEmpty)     // the rule wins: no evidence, no block
        XCTAssertNil(d.brain.block)
        _ = d.window(70, "w:docs")
        XCTAssertTrue(Driver.requests(d.window(80, "w:yt")).isEmpty)                           // back on it: still ON by rule, no judgment asked
        XCTAssertEqual(d.brain.emBeacon.state, "resting")
    }

    func testMarkRelevantTeachesTheSite() {
        var d = Driver(); d.start()
        _ = d.window(0, "w:a1", site: "s:khan")
        _ = d.judge(3.5, observed: 0, "w:a1", .offTask, strong: true)
        let fx = d.go(10, .userAction(.markRelevant, minutes: nil))
        XCTAssertTrue(fx.contains(.learnRule(scope: "project", kind: "allow", keyType: "site", key: "s:khan")))
        // another page on the same site is ON by rule: no request
        XCTAssertTrue(Driver.requests(d.window(20, "w:a2", site: "s:khan")).isEmpty)
    }

    func testDismissWithdrawsTheCardOnly() {
        var d = Driver(); d.start()
        _ = d.window(0, "w:yt")
        var t = 1.0
        var fired = false
        while t < 200 && !fired {
            if Int(t) % 14 == 4 { _ = d.judge(t, observed: t - 3.5, "w:yt", .offTask, strong: true, content: "c") }
            fired = d.go(t, .tick).contains { if case .interrupt = $0 { return true } else { return false } }
            t += 1
        }
        XCTAssertTrue(fired)
        XCTAssertEqual(d.go(t, .userAction(.dismiss, minutes: nil)), [.withdraw(what: "card")])
        XCTAssertEqual(d.brain.focus, .confirmed)  // nothing else changes; the repeat schedule stands
    }

    func testStaleAndMismatchedJudgmentsAreDiscarded() {
        var d = Driver(); d.start()
        _ = d.window(10, "w:a")
        XCTAssertTrue(d.judge(12, observed: 5, "w:a", .offTask, strong: true).isEmpty)           // captured before the window appeared
        XCTAssertNil(d.brain.block)
        XCTAssertTrue(d.judge(14, observed: 11, "w:other", .offTask, strong: true).isEmpty)       // different window
        XCTAssertNil(d.brain.block)
        _ = d.judge(20, observed: 18, "w:a", .unsure)
        XCTAssertNotNil(d.brain.block)
        _ = d.judge(30, observed: 15, "w:a", .onTask)                                             // older than the last judgment
        XCTAssertEqual(d.brain.lastEvidence?.at, 18)
        var idle = Brain(); XCTAssertTrue(idle.step(0, .tick).isEmpty)                           // no session
    }

    func testRuleOffTaskStartsAFlaggedBlockWithoutAskingTheModel() {
        var d = Driver(); d.start()
        XCTAssertTrue(Driver.requests(d.window(0, "w:bad", rule: .offTask)).isEmpty)
        XCTAssertEqual(d.brain.block?.flagged, true)
        let drift = d.ticks(1, 30).first { $0.1.contains(.beacon(state: "drifting", reason: nil)) }
        XCTAssertEqual(drift?.0, 25)
    }

    func testStrictGateRepeatMeetsTheRateCap() {
        var d = Driver(); d.start(.strict)
        _ = d.window(0, "w:yt")
        var interrupts: [Double] = []
        var t = 0.0
        while t < 900 {
            if t >= 4 && Int(t) % 10 == 4 { _ = d.judge(t, observed: t - 3.5, "w:yt", .offTask, strong: true, content: "c") }
            let fx = d.go(t, .tick)
            if fx.contains(where: { if case .interrupt = $0 { return true } else { return false } }) { interrupts.append(t); }
            if d.brain.interruptOpen != nil && interrupts.last.map({ t - $0 >= 5 }) == true { _ = d.go(t, .userAction(.dismiss, minutes: nil)) }
            t += 1
        }
        XCTAssertGreaterThanOrEqual(interrupts.count, 3)
        XCTAssertEqual(interrupts[1] - interrupts[0], 180, accuracy: 1.5)
        XCTAssertGreaterThanOrEqual(interrupts[2] - interrupts[0], 600)   // the third is deferred by the cap
    }
}

/// Deterministic pseudo-random event streams, checked against the spec's invariants (PLAN 9.3).
struct LCG { var s: UInt64; mutating func next(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) % UInt64(n)) } }

final class BrainPropertyTests: XCTestCase {
    static let wins = [("w:a", "s:a"), ("w:b", "s:a"), ("w:c", "s:c"), ("w:d", "s:d")]

    func run(seed: UInt64, strongAllowed: Bool, check: (inout Brain, Double, [Effect]) -> Void) -> [(Double, [Effect])] {
        var r = LCG(s: seed)
        var b = Brain()
        var cfg = SessionConfig(); cfg.preset = [Preset.gentle, .standard, .strict][r.next(3)]; cfg.shadow = r.next(5) == 0
        var all: [(Double, [Effect])] = []
        var t = 0.0
        let fx0 = b.step(0, .sessionStart(cfg)); all.append((0, fx0)); check(&b, 0, fx0)
        for _ in 0..<1500 {
            t += 1
            for _ in 0..<r.next(3) {
                let w = Self.wins[r.next(4)]
                var ev: Event
                switch r.next(40) {
                case 0...9: ev = .windowChange(WindowChangeInput(windowKey: w.0, siteKey: w.1, ruleLabel: r.next(25) == 0 ? .onTask : nil))
                case 10...29:
                    var j = JudgmentInput(observedAt: t - Double(r.next(8)) * 0.5, windowKey: w.0, contentKey: "c\(r.next(3))",
                                          label: [.onTask, .unsure, .offTask][r.next(3)])
                    j.strong = strongAllowed && r.next(2) == 0
                    if r.next(15) == 0 { j.flag = .refusal }
                    ev = .judgment(j)
                case 30: ev = .userAction([.pause, .resume, .dismiss, .nextStep, .backToTask, .thatWasFine, .markOffTask][r.next(7)], minutes: nil)
                case 31: ev = .userAction(.breakTime, minutes: 5)
                case 32: ev = .userAction(.snooze, minutes: 15)
                case 33: ev = [.idle, .active, .sleep, .wake][r.next(4)]
                case 34: ev = [.meetingStart, .meetingEnd][r.next(2)]
                case 35: ev = [.sensitiveEntered, .sensitiveLeft][r.next(2)]
                case 36: ev = .powerChange(constrained: r.next(2) == 0, critical: r.next(8) == 0)
                case 37: ev = .userAction(.panic, minutes: nil)
                default: ev = .tick
                }
                let fx = b.step(t, ev); all.append((t, fx)); check(&b, t, fx)
            }
            let fx = b.step(t, .tick); all.append((t, fx)); check(&b, t, fx)
        }
        return all
    }

    func testInvariantsHoldOnRandomStreams() {
        for seed in 1...120 {
            var interruptTimes: [Double] = []
            _ = run(seed: UInt64(seed), strongAllowed: true) { b, t, fx in
                guard let s = b.session else { return }
                for e in fx {
                    if case .interrupt = e {
                        XCTAssertEqual(b.lastEvidence?.cls, .strong, "seed \(seed) t=\(t): interrupt without strong latest evidence")
                        interruptTimes.append(t)
                        let recent = interruptTimes.filter { $0 > t - 600 && $0 <= t }
                        XCTAssertLessThanOrEqual(recent.count, 2, "seed \(seed) t=\(t): rate cap broken")
                        XCTAssertFalse(s.shadow, "seed \(seed): interrupt in shadow mode")
                    }
                }
                let lvl = Brain.level(b.seg, t)
                XCTAssertLessThanOrEqual(lvl, s.policy.veilCap, "seed \(seed) t=\(t): veil above cap")
                if b.isHeld {
                    XCTAssertEqual(b.seg.to, 0, "seed \(seed) t=\(t): hold left a veil target")
                    XCTAssertFalse(b.emTimerVisible, "seed \(seed) t=\(t): hold left the timer visible")
                    XCTAssertEqual(b.emBeacon.state, "paused")
                }
                if s.shadow { XCTAssertTrue(b.emBeacon.state == "resting" || b.emBeacon.state == "paused") }
            }
        }
    }

    func testUnsureAndWeakEvidenceNeverInterrupts() {
        for seed in 200...260 {
            _ = run(seed: UInt64(seed), strongAllowed: false) { b, t, fx in
                for e in fx { if case .interrupt = e { XCTFail("seed \(seed) t=\(t): interrupt without any strong verdict") } }
                if b.focus == .confirmed || b.focus == .persisting { XCTFail("seed \(seed) t=\(t): reached Confirmed without strong evidence") }
            }
        }
    }

    func testSameInputsGiveIdenticalEffects() {
        let a = run(seed: 7, strongAllowed: true) { _, _, _ in }
        let b = run(seed: 7, strongAllowed: true) { _, _, _ in }
        XCTAssertEqual(a.count, b.count)
        for (x, y) in zip(a, b) { XCTAssertEqual(x.0, y.0); XCTAssertEqual(x.1, y.1) }
    }
}
