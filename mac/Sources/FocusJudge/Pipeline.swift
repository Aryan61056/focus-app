import Foundation

public enum Stage: String, Codable, Sendable { case sensitive, rule, guarded, model }

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

/// How sure the model must be before an off-task call counts as off task. Lower flags more distractions and also more things that are
/// really work; the brain still needs sustained agreement over time before anything is shown (owner, 2026-10-13: "call out
/// distractions even if it isn't completely sure").
public enum Sensitivity: String, CaseIterable, Identifiable, Sendable {
    case careful, balanced, proactive
    public var id: String { rawValue }
    public var minOffConfidence: Int { switch self { case .careful: return 95; case .balanced: return 80; case .proactive: return 60 } }
    public var title: String { switch self { case .careful: return "Careful"; case .balanced: return "Balanced"; case .proactive: return "Proactive" } }
}

public enum Pipeline {
    /// The first judge must report at least this much confidence before a window can count as off task. Measured 2026-10-02 on
    /// 82 scenarios that reach the model: every off_task call that was really on-task work had confidence 90 or less (the model says
    /// 95 when it is sure), while 32 of 36 real distractions had 95. Tuned on spent sets: see docs/STATUS.md.
    public static let minOffConfidence = 95

    /// Two-judge rule: confirmed off_task only when the reason-first judge says off_task AND the second judge does not say on_task.
    /// A reason-first on_task stays on_task. Else unsure. (The second judge is the "does it serve the task" question since 2026-10-02;
    /// docs/S1-accuracy.md describes the earlier relation judge.)
    public static func combine(first: Label, second: Label) -> Label {
        if first == .offTask && second != .onTask { return .offTask }
        if first == .onTask { return .onTask }
        return .unsure
    }

    public static func judge(_ m: Moment, with judge: Judge, useRules: Bool = true, useGuard: Bool = true,
                             minOffConfidence: Int = Pipeline.minOffConfidence) async -> Judgement {
        if useRules && Rules.isSensitive(m) {
            return Judgement(label: .unsure, stage: .sensitive, reason: "sensitive window, not read", latencyMs: 0)
        }
        if useRules, let hit = Rules.stage1(m) {
            return Judgement(label: hit.label, stage: .rule, reason: hit.rule, latencyMs: 0)
        }
        // On-screen text that talks to the AI is not judged: unsure, so it can never lead to a nudge (docs/T7-injection.md).
        if useGuard && Rules.looksInjected(m) {
            return Judgement(label: .unsure, stage: .guarded, reason: "This window's text contains instructions aimed at the AI. Focus ignored it.", latencyMs: 0)
        }
        let prompt = Prompts.prompt(for: m)
        var first = await judge.reasonFirst(prompt: prompt)
        // An off_task the model is not sure enough about is "not sure". The bar is the user's Sensitivity setting; 95 is the careful default of the eval.
        if first.label == .offTask, let c = first.confidence, c < minOffConfidence { first.label = .unsure }
        // Only a possible off_task needs the second opinion; skipping it otherwise halves the model calls.
        if first.label != .offTask || first.error != nil {
            return Judgement(label: combine(first: first.label, second: .unsure), stage: .model, reason: first.reason,
                             firstLabel: first.label, latencyMs: first.latencyMs, error: first.error)
        }
        let second = await judge.relation(prompt: prompt)
        // A refusal or guardrail error on either judge is "unsure plus a flag", never a confirmed off_task.
        let errored = first.error != nil || second.error != nil
        return Judgement(label: errored ? .unsure : combine(first: first.label, second: second.label), stage: .model, reason: first.reason,
                         firstLabel: first.label, secondLabel: second.label,
                         latencyMs: first.latencyMs + second.latencyMs, error: first.error ?? second.error)
    }
}
