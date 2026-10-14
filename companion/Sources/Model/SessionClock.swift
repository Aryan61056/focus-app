import Foundation
import FocusLinkNet

/// The Mac sends the clock when something changes; the phone keeps time from there. Both ends only ever compare durations
/// ("this many seconds when I sent it"), so their wall clocks never need to agree.
struct SessionClock: Equatable {
    var state: SessionState
    var receivedAt: Date

    func seconds(at date: Date) -> Double {
        guard state.clockRunning else { return max(0, state.clockSeconds) }
        let elapsed = max(0, date.timeIntervalSince(receivedAt))
        return max(0, state.timed ? state.clockSeconds - elapsed : state.clockSeconds + elapsed)
    }

    /// How far through a timed session, 0...1. Nil for an open one.
    func progress(at date: Date) -> Double? {
        guard state.timed, state.totalSeconds > 0 else { return nil }
        return min(1, max(0, 1 - seconds(at: date) / state.totalSeconds))
    }

    func offTopicSeconds(at date: Date) -> Double {
        state.offTopicSeconds + (state.offTopicRunning ? max(0, date.timeIntervalSince(receivedAt)) : 0)
    }
}
