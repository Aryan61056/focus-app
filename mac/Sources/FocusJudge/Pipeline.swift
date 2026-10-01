import Foundation

public enum Stage: String, Codable, Sendable { case sensitive, rule, model }

/// The outcome for one moment. `label == .offTask` is a candidate for a nudge, never a nudge by itself:
/// the brain still requires sustained agreement over time.
public struct Judgement: Sendable {
    public var label: Label
    public var stage: Stage
    public var reason: String
    public var firstLabel: Label?
    public var secondLabel: Label?
    public var latencyMs: Double
    public var error: String?
}

public enum Pipeline {
    /// Frozen two-judge rule (docs/S1-accuracy.md): confirmed off_task only when the reason-first judge says
    /// off_task AND the relation judge does not say on_task. A reason-first on_task stays on_task. Else unsure.
    public static func combine(first: Label, second: Label) -> Label {
        if first == .offTask && second != .onTask { return .offTask }
        if first == .onTask { return .onTask }
        return .unsure
    }

    public static func judge(_ m: Moment, with judge: Judge, useRules: Bool = true) async -> Judgement {
        if useRules && Rules.isSensitive(m) {
            return Judgement(label: .unsure, stage: .sensitive, reason: "sensitive window, not read", latencyMs: 0)
        }
        if useRules, let hit = Rules.stage1(m) {
            return Judgement(label: hit.label, stage: .rule, reason: hit.rule, latencyMs: 0)
        }
        let prompt = Prompts.prompt(for: m)
        let first = await judge.reasonFirst(prompt: prompt)
        // Only a possible off_task needs the second opinion; skipping it otherwise halves the model calls.
        if first.label != .offTask {
            return Judgement(label: combine(first: first.label, second: .unsure), stage: .model, reason: first.reason,
                             firstLabel: first.label, latencyMs: first.latencyMs, error: first.error)
        }
        let second = await judge.relation(prompt: prompt)
        return Judgement(label: combine(first: first.label, second: second.label), stage: .model, reason: first.reason,
                         firstLabel: first.label, secondLabel: second.label,
                         latencyMs: first.latencyMs + second.latencyMs, error: first.error ?? second.error)
    }
}
