import Foundation

/// What the Mac is doing right now. Sent whenever it changes, never once a second: the phone runs the clock itself
/// from `clockSeconds` and `clockRunning`, so the two devices never need to agree on the time of day.
public struct SessionState: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case idle, onTask, unsure, drifting, recovering, paused, onBreak }

    public var sessionID: UUID?
    public var phase: Phase
    public var task: String
    public var timed: Bool
    /// Remaining seconds for a timed session, elapsed seconds for an open one, at the moment this was sent.
    public var clockSeconds: Double
    public var clockRunning: Bool
    /// The length of a timed session. Zero for an open one.
    public var totalSeconds: Double
    public var offTopicSeconds: Double
    public var offTopicRunning: Bool
    /// How far the Mac's warning has climbed: 0 warned, 1 check-in, 2 pause screen, 3 hid the app.
    public var driftStep: Int
    /// A practice session: Hushd watches but does not nudge.
    public var practice: Bool
    /// A short line the Mac wants shown, such as "Back in 40 s". Nil most of the time.
    public var note: String?

    public init(sessionID: UUID? = nil, phase: Phase = .idle, task: String = "", timed: Bool = false, clockSeconds: Double = 0,
                clockRunning: Bool = false, totalSeconds: Double = 0, offTopicSeconds: Double = 0, offTopicRunning: Bool = false,
                driftStep: Int = 0, practice: Bool = false, note: String? = nil) {
        self.sessionID = sessionID; self.phase = phase; self.task = task; self.timed = timed; self.clockSeconds = clockSeconds
        self.clockRunning = clockRunning; self.totalSeconds = totalSeconds; self.offTopicSeconds = offTopicSeconds
        self.offTopicRunning = offTopicRunning; self.driftStep = driftStep; self.practice = practice; self.note = note
    }

    public static let idle = SessionState()
    public var isActive: Bool { phase != .idle }
}
