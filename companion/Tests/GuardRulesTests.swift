import Testing
import Foundation
import FocusLinkNet
@testable import FocusCompanion

struct GuardRulesTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func clock(_ phase: SessionState.Phase, timed: Bool = false, seconds: Double = 600, practice: Bool = false, at: Date? = nil) -> SessionClock {
        SessionClock(state: SessionState(phase: phase, timed: timed, clockSeconds: seconds, clockRunning: true, practice: practice), receivedAt: at ?? t0)
    }

    @Test func bouncesWhileWorkingWhenTheMacAnswered() {
        for p in [SessionState.Phase.onTask, .unsure, .drifting, .recovering] {
            #expect(GuardRules.shouldBounce(clock(p), live: true, now: t0.addingTimeInterval(3 * 3600)))
        }
    }
    @Test func leavesEveryAppOpenOnBreakPauseIdleAndPractice() {
        for p in [SessionState.Phase.onBreak, .paused, .idle] { #expect(!GuardRules.shouldBounce(clock(p), live: true, now: t0)) }
        #expect(!GuardRules.shouldBounce(clock(.onTask, practice: true), live: true, now: t0))
    }
    @Test func aRecentNoteStillCountsWhenTheMacCannotBeReached() {
        #expect(GuardRules.shouldBounce(clock(.onTask), live: false, now: t0.addingTimeInterval(5 * 60)))
    }
    @Test func anOldNoteIsNotTrusted() {
        #expect(!GuardRules.shouldBounce(clock(.onTask), live: false, now: t0.addingTimeInterval(GuardRules.staleAfter + 1)))
    }
    @Test func aTimedSessionThatMustHaveEndedIsNotGuarded() {
        #expect(!GuardRules.shouldBounce(clock(.onTask, timed: true, seconds: 120), live: false, now: t0.addingTimeInterval(180)))
        #expect(GuardRules.shouldBounce(clock(.onTask, timed: true, seconds: 600), live: false, now: t0.addingTimeInterval(180)))
    }
    @Test func theNoteSurvivesBeingSaved() throws {
        let suite = UserDefaults(suiteName: "guard-test-\(UUID().uuidString)")!
        let cache = GuardCache(defaults: suite)
        #expect(cache.load() == nil)
        cache.save(clock(.drifting))
        #expect(cache.load()?.state.phase == .drifting)
        cache.clear()
        #expect(cache.load() == nil)
    }
}

@MainActor struct GuardSwitchTests {
    @Test func theSwitchTurnsTheGuardOffWhateverTheSessionIs() async {
        let model = AppModel(store: .memory())
        model.blocker.enabled = false
        #expect(await model.guardCheck(record: false) == .switchedOff)
        model.blocker.enabled = true   // leave the shared defaults as other tests expect
    }
}
