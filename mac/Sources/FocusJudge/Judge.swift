import Foundation

/// What the model says about one moment. `relation` is set by the relation judge only.
public struct Verdict: Sendable {
    public var label: Label
    public var reason: String
    public var relation: String?
    public var topic: String?
    public var latencyMs: Double
    public var error: String?

    public init(label: Label, reason: String = "", relation: String? = nil, topic: String? = nil,
                latencyMs: Double = 0, error: String? = nil) {
        self.label = label; self.reason = reason; self.relation = relation; self.topic = topic
        self.latencyMs = latencyMs; self.error = error
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
    /// Relation verdict (instructions v2), already mapped to a label.
    func relation(prompt: String) async -> Verdict
}
