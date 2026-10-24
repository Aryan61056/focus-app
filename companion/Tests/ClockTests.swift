import Testing
import Foundation
import FocusLinkNet
@testable import FocusCompanion

struct ClockTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func timedClockCountsDownFromWhenItArrived() {
        let c = SessionClock(state: SessionState(phase: .onTask, timed: true, clockSeconds: 600, clockRunning: true, totalSeconds: 1500), receivedAt: t0)
        #expect(c.seconds(at: t0) == 600)
        #expect(c.seconds(at: t0.addingTimeInterval(90)) == 510)
        #expect(c.seconds(at: t0.addingTimeInterval(9999)) == 0)
    }
    @Test func openClockCountsUp() {
        let c = SessionClock(state: SessionState(phase: .onTask, clockSeconds: 120, clockRunning: true), receivedAt: t0)
        #expect(c.seconds(at: t0.addingTimeInterval(30)) == 150)
    }
    @Test func pausedClockStandsStill() {
        let c = SessionClock(state: SessionState(phase: .paused, timed: true, clockSeconds: 400, clockRunning: false, totalSeconds: 1500), receivedAt: t0)
        #expect(c.seconds(at: t0.addingTimeInterval(500)) == 400)
    }
    @Test func progressIsShareOfTheTimedSessionDone() throws {
        let c = SessionClock(state: SessionState(phase: .onTask, timed: true, clockSeconds: 1000, clockRunning: true, totalSeconds: 2000), receivedAt: t0)
        #expect(c.progress(at: t0) == 0.5)
        #expect(SessionClock(state: SessionState(phase: .onTask, clockRunning: true), receivedAt: t0).progress(at: t0) == nil)
    }
    @Test func awayTimeKeepsRunningOnlyWhileDrifting() {
        let c = SessionClock(state: SessionState(phase: .drifting, clockRunning: true, offTopicSeconds: 20, offTopicRunning: true), receivedAt: t0)
        #expect(c.offTopicSeconds(at: t0.addingTimeInterval(10)) == 30)
        let still = SessionClock(state: SessionState(phase: .onTask, clockRunning: true, offTopicSeconds: 20), receivedAt: t0)
        #expect(still.offTopicSeconds(at: t0.addingTimeInterval(10)) == 20)
    }
}

struct PairingFieldTests {
    @Test func formatsAsYouType() {
        #expect(PairingView.format("k7qm2xd9pwrb4htn") == "K7QM-2XD9-PWRB-4HTN")
        #expect(PairingView.format("k7q") == "K7Q")
        #expect(PairingView.format("K7QM-2XD9") == "K7QM-2XD9")
        #expect(PairingView.format("k7qm 2xd9!!") == "K7QM-2XD9")
        #expect(PairingView.format("0123456789ABCDEFGHJKM").filter { $0 != "-" }.count == 16)
    }
}

struct PickupReminderTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private func clock(_ phase: SessionState.Phase, timed: Bool = false, seconds: Double = 600, practice: Bool = false) -> SessionClock {
        SessionClock(state: SessionState(phase: phase, task: "Calc", timed: timed, clockSeconds: seconds, clockRunning: true, totalSeconds: timed ? 1500 : 0, practice: practice), receivedAt: now)
    }

    @Test func remindsWhileWorkingOrDrifting() {
        for p in [SessionState.Phase.onTask, .unsure, .drifting, .recovering] {
            #expect(PickupReminder.plan(clock: clock(p), live: true, now: now, lastShown: nil) == PickupReminder.delay)
        }
    }
    @Test func neverRemindsWhenNothingIsRunningOrYouPaused() {
        #expect(PickupReminder.plan(clock: clock(.idle), live: true, now: now, lastShown: nil) == nil)
        #expect(PickupReminder.plan(clock: clock(.paused), live: true, now: now, lastShown: nil) == nil)
        #expect(PickupReminder.plan(clock: clock(.onBreak), live: true, now: now, lastShown: nil) == nil)
    }
    @Test func neverRemindsWithoutAConnectionOrDuringPractice() {
        #expect(PickupReminder.plan(clock: clock(.onTask), live: false, now: now, lastShown: nil) == nil)
        #expect(PickupReminder.plan(clock: clock(.onTask, practice: true), live: true, now: now, lastShown: nil) == nil)
    }
    @Test func noReminderForASessionAboutToEnd() {
        #expect(PickupReminder.plan(clock: clock(.onTask, timed: true, seconds: 90), live: true, now: now, lastShown: nil) == nil)
        #expect(PickupReminder.plan(clock: clock(.onTask, timed: true, seconds: 400), live: true, now: now, lastShown: nil) != nil)
    }
    @Test func atMostOneEveryFiveMinutes() {
        #expect(PickupReminder.plan(clock: clock(.onTask), live: true, now: now, lastShown: now.addingTimeInterval(-120)) == nil)
        #expect(PickupReminder.plan(clock: clock(.onTask), live: true, now: now, lastShown: now.addingTimeInterval(-400)) != nil)
    }
}

struct PairingLinkOpenTests {
    @Test func aBadLinkIsExplainedNotIgnored() {
        let model = AppModel(store: .memory())
        model.open(URL(string: "focuslink://pair?c=nope")!)
        #expect(model.notice == "That isn't a Hushd pairing code.")
        #expect(model.linking == .idle)
    }
}
