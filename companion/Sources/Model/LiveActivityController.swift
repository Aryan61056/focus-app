@preconcurrency import ActivityKit
import Foundation
import FocusLinkNet

/// Keeps one Live Activity in step with the Mac's session: on the lock screen and in the Dynamic Island, so the task is
/// the first thing in front of you when you pick the phone up. The system draws the timers from dates, so they stay right
/// without this app running; only a change of state needs the app awake.
@MainActor final class LiveActivityController {
    private var activity: Activity<FocusActivityAttributes>?

    func sync(_ clock: SessionClock) {
        let s = clock.state
        guard s.isActive else { return end() }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let phase = Self.phase(s.phase)
        let content = FocusActivityAttributes.ContentState(
            phase: phase,
            endsAt: s.clockRunning && s.timed ? clock.receivedAt.addingTimeInterval(s.clockSeconds) : nil,
            since: s.clockRunning && !s.timed ? clock.receivedAt.addingTimeInterval(-s.clockSeconds) : nil,
            frozenSeconds: s.clockSeconds)
        if let activity, activity.attributes.task == s.task {
            Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
        } else {
            end()
            activity = try? Activity.request(attributes: FocusActivityAttributes(task: s.task, timed: s.timed), content: ActivityContent(state: content, staleDate: nil))
        }
    }

    func end() {
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }

    private static func phase(_ p: SessionState.Phase) -> FocusActivityAttributes.ContentState.Phase {
        switch p {
        case .idle, .onTask: .onTask
        case .unsure: .unsure
        case .drifting: .drifting
        case .recovering: .recovering
        case .paused: .paused
        case .onBreak: .onBreak
        }
    }
}
