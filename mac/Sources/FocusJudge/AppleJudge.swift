import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Apple's on-device system language model. Needs macOS 26 and Apple Intelligence enabled.
/// A fresh session per request keeps verdicts from bleeding into each other. Greedy sampling.
@available(macOS 26.0, *)
public struct AppleJudge: Judge {
    @Generable
    enum VerdictLabel { case on_task, unsure, off_task }

    @Generable
    enum ContentKind { case video, article, chat, code, document, feed, search, game, shopping, other }

    @Generable
    struct ReasonFirstOutput {
        @Guide(description: "At most 14 words explaining the verdict")
        var reason: String
        @Guide(description: "One or two words naming the activity, such as lecture, social media, coding")
        var category: String
        var content_kind: ContentKind
        @Guide(description: "Verdict for the window the user is looking at")
        var label: VerdictLabel
        @Guide(description: "How sure you are, 0 to 100", .range(0...100))
        var confidence: Int
    }

    @Generable
    enum RelationChoice { case directly_serves, supporting, neutral, unclear, different_activity }

    @Generable
    struct RelationOutput {
        @Guide(description: "What the main content of the window is about, at most 10 words")
        var topic: String
        var relation: RelationChoice
        @Guide(description: "At most 14 words explaining the choice")
        var reason: String
    }

    public init() {}

    public enum Availability: Equatable, Sendable { case available, unavailable(String) }

    public static var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(let reason): return .unavailable(String(describing: reason))
        }
    }

    public func reasonFirst(prompt: String) async -> Verdict {
        let start = Date()
        do {
            let session = LanguageModelSession(instructions: Prompts.instructions(.v1))
            let out = try await session.respond(to: prompt, generating: ReasonFirstOutput.self,
                                                options: GenerationOptions(sampling: .greedy)).content
            let label: Label
            switch out.label { case .on_task: label = .onTask; case .unsure: label = .unsure; case .off_task: label = .offTask }
            return Verdict(label: label, reason: out.reason, latencyMs: Date().timeIntervalSince(start) * 1000)
        } catch {
            return Verdict(label: .unsure, latencyMs: Date().timeIntervalSince(start) * 1000, error: Self.classify(error))
        }
    }

    public func relation(prompt: String) async -> Verdict {
        let start = Date()
        do {
            let session = LanguageModelSession(instructions: Prompts.instructions(.v2))
            let out = try await session.respond(to: prompt, generating: RelationOutput.self,
                                                options: GenerationOptions(sampling: .greedy)).content
            guard let rel = Relation(rawValue: String(describing: out.relation)) else {
                return Verdict(label: .unsure, latencyMs: Date().timeIntervalSince(start) * 1000, error: "unknown relation")
            }
            return Verdict(label: rel.label, reason: out.reason, relation: rel.rawValue, topic: out.topic,
                           latencyMs: Date().timeIntervalSince(start) * 1000)
        } catch {
            return Verdict(label: .unsure, latencyMs: Date().timeIntervalSince(start) * 1000, error: Self.classify(error))
        }
    }

    static func classify(_ error: Error) -> String {
        let d = String(describing: error).lowercased()
        if d.contains("guardrail") { return "guardrail" }
        if d.contains("refus") { return "refusal" }
        if d.contains("context") { return "context_window" }
        return "error"
    }
}
#endif
