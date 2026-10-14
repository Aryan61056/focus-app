import ActivityKit
import Foundation

/// The lock screen and Dynamic Island card for a running session. The timers are drawn by the system from dates,
/// so they keep counting even though this app is not running to update them.
nonisolated struct FocusActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable { case onTask, unsure, drifting, recovering, paused, onBreak }
        var phase: Phase
        /// Timed and running: when it ends. The card counts down to it.
        var endsAt: Date?
        /// Open and running: when it began. The card counts up from it.
        var since: Date?
        /// Paused or on a break: the frozen figure, in seconds.
        var frozenSeconds: Double
    }
    var task: String
    var timed: Bool
}
