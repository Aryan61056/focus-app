import Foundation

/// What the model says about one moment. `relation` is set by the relation judge only.
public struct Verdict: Sendable {
    public var label: Label
    public var reason: String
    public var relation: String?
    public var topic: String?
    public var latencyMs: Double
    public var error: String?
    /// How sure the model says it is, 0 to 100. nil when the judge does not report one.
    public var confidence: Int?

    public init(label: Label, reason: String = "", relation: String? = nil, topic: String? = nil,
                latencyMs: Double = 0, error: String? = nil, confidence: Int? = nil) {
        self.label = label; self.reason = reason; self.relation = relation; self.topic = topic
        self.latencyMs = latencyMs; self.error = error; self.confidence = confidence
    }
}

public enum Relation: String, Sendable {
    case directlyServes = "directly_serves", supporting, neutral, unclear, differentActivity = "different_activity"

    /// Policy lives here, not in the model: only a different activity can ever become off_task.
    public var label: Label {
        switch self {
        case .directlyServes, .supporting: return .onTask
        case .neutral, .unclear: return .unsure
        case .differentActivity: return .offTask
        }
    }
}

/// A source of verdicts. Implementations must not touch the network.
public protocol Judge: Sendable {
    /// Reason-first verdict (instructions v1).
    func reasonFirst(prompt: String) async -> Verdict
    /// Second opinion on a possible off_task (instructions v3), already mapped to a label.
    func relation(prompt: String) async -> Verdict
}
