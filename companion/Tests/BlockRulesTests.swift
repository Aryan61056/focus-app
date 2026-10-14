import Testing
import Foundation
import FocusLinkNet
@testable import FocusCompanion

struct BlockRulesTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func state(_ phase: SessionState.Phase, timed: Bool = false, seconds: Double = 0, practice: Bool = false) -> SessionState {
        SessionState(phase: phase, timed: timed, clockSeconds: seconds, clockRunning: true, practice: practice)
    }
    private func shield(_ s: SessionState, enabled: Bool = true, picked: Bool = true, allowed: Bool = true, canBlock: Bool = true) -> Bool {
        BlockRules.shouldShield(s, enabled: enabled, hasSelection: picked, authorized: allowed, canBlock: canBlock)
    }

    @Test func coversWhileWorkingIncludingDriftAndRecovery() {
        for p in [SessionState.Phase.onTask, .unsure, .drifting, .recovering] { #expect(shield(state(p))) }
    }
    @Test func opensOnBreakPauseAndWhenIdle() {
        for p in [SessionState.Phase.onBreak, .paused, .idle] { #expect(!shield(state(p))) }
    }
    @Test func practiceIsNeverCovered() { #expect(!shield(state(.onTask, practice: true))) }
    @Test func needsAChoiceAccessAndTheSwitch() {
        #expect(!shield(state(.onTask), enabled: false))
        #expect(!shield(state(.onTask), picked: false))
        #expect(!shield(state(.onTask), allowed: false))
    }
    @Test func demoNeverCoversRealApps() { #expect(!shield(state(.onTask), canBlock: false)) }

    @Test func timedSessionEndsJustAfterItsClock() {
        let end = BlockRules.safetyEnd(for: state(.onTask, timed: true, seconds: 1800), now: now)
        #expect(end == now.addingTimeInterval(1800 + BlockRules.grace))
    }
    @Test func iosNeedsAtLeastFifteenMinutes() {
        let end = BlockRules.safetyEnd(for: state(.onTask, timed: true, seconds: 60), now: now)
        #expect(end == now.addingTimeInterval(BlockRules.shortestSchedule))
    }
    @Test func openSessionStillGetsAnEnd() {
        #expect(BlockRules.safetyEnd(for: state(.onTask, seconds: 90), now: now) == now.addingTimeInterval(BlockRules.openSessionCap))
    }
}
