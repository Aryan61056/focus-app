import Foundation
import FocusJudge
import FocusBrain

public struct Project: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var context = ""
    public var nextStep = ""
    public var profile = ProjectProfile()
    public var createdAt = Date()
    public init(name: String) { self.name = name }
}

/// One slice of a session's timeline. Seconds only: no window titles or text are ever stored (CLAUDE.md principle 2).
public struct TimelineSegment: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case on, unsure, off, gap }
    public var kind: Kind
    public var seconds: Double
    public init(_ kind: Kind, _ seconds: Double) { self.kind = kind; self.seconds = seconds }
}

/// How many checks Focus made in a session and what it concluded. Counts only: no titles, no text.
public struct ReadStats: Codable, Equatable, Sendable {
    public var model = 0, rule = 0, onTask = 0, unsure = 0, offTask = 0
    public var total: Int { onTask + unsure + offTask }
    public init() {}
}

public struct SessionRecord: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var projectId: UUID?
    public var task: String
    public var timed: Bool
    public var start: Date
    public var end: Date
    public var activeSeconds: Double
    public var offTopicSeconds: Double
    public var unsureSeconds: Double
    public var drifts: Int
    public var interrupts: Int
    public var refusals: Int
    public var shadowMarks: Int
    public var segments: [TimelineSegment]
    public var note = ""
    public var reads: ReadStats?

    public var onTaskSeconds: Double { max(0, activeSeconds - offTopicSeconds - unsureSeconds) }

    public init(projectId: UUID?, task: String, timed: Bool, start: Date, end: Date, activeSeconds: Double, offTopicSeconds: Double, unsureSeconds: Double,
                drifts: Int, interrupts: Int, refusals: Int, shadowMarks: Int, segments: [TimelineSegment], reads: ReadStats? = nil) {
        self.projectId = projectId; self.task = task; self.timed = timed; self.start = start; self.end = end; self.activeSeconds = activeSeconds
        self.offTopicSeconds = offTopicSeconds; self.unsureSeconds = unsureSeconds; self.drifts = drifts; self.interrupts = interrupts
        self.refusals = refusals; self.shadowMarks = shadowMarks; self.segments = segments; self.reads = reads
    }
}

/// A moment practice mode would have nudged about, kept for the Review screen. Category-level text only.
public struct ReviewMoment: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var sessionId: UUID?
    public var projectId: UUID?
    public var at: Date
    public var windowKey: String
    public var siteKey: String
    public var answer: String?   // "right" or "fine"
    /// The judge's one-line reason, kept only until the moment is answered (the store drops it then).
    public var reason: String?

    public init(sessionId: UUID?, projectId: UUID?, at: Date, windowKey: String, siteKey: String, reason: String? = nil) {
        self.sessionId = sessionId; self.projectId = projectId; self.at = at; self.windowKey = windowKey; self.siteKey = siteKey; self.reason = reason
    }
}

struct StoreFile: Codable {
    var version = 1
    var projects: [Project] = []
    var sessions: [SessionRecord] = []
    var review: [ReviewMoment] = []
}
