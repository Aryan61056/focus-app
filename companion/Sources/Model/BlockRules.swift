import Foundation
import FocusLinkNet

/// When the phone covers the apps the person chose. Pure, so it can be tested without Screen Time.
enum BlockRules {
    /// An open session has no end time, so the block gets one anyway: the Mac may never be heard from again.
    static let openSessionCap: TimeInterval = 4 * 3600
    /// iOS will not run a schedule shorter than this.
    static let shortestSchedule: TimeInterval = 15 * 60
    /// A little past the end of a timed session, so +5 min pressed at the last second does not leave a gap.
    static let grace: TimeInterval = 2 * 60

    /// Covered while working (on task, unsure, drifting, getting back). Open during a pause or a break, and never in practice,
    /// which is meant to be silent.
    static func shouldShield(_ s: SessionState, enabled: Bool, hasSelection: Bool, authorized: Bool, canBlock: Bool = true) -> Bool {
        guard enabled, hasSelection, authorized, canBlock, !s.practice else { return false }
        switch s.phase {
        case .onTask, .unsure, .drifting, .recovering: return true
        case .idle, .paused, .onBreak: return false
        }
    }

    /// When iOS should lift the block by itself if nothing else does.
    static func safetyEnd(for s: SessionState, now: Date) -> Date {
        let wanted = s.timed ? s.clockSeconds + grace : openSessionCap
        return now.addingTimeInterval(max(shortestSchedule, wanted))
    }
}
