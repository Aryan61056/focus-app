// fmjudge: runs Apple's on-device system language model as the focus-app relevance judge.
// Protocol: JSON lines on stdin -> JSON lines on stdout. First line out is {"status": ...}.
// Request:  {"id", "instructions", "prompt", "order": "reason-first" | "label-first" | "relation"}
// Response: {"id", "label", "confidence", "reason", "category", "content_kind"} or {"id", "error", "detail"}
// Nothing here touches the network. A fresh session is used per request so verdicts never bleed together.

import Foundation
import FoundationModels

@Generable
enum Label {
    case on_task
    case unsure
    case off_task
}

@Generable
enum ContentKind {
    case video, article, chat, code, document, feed, search, game, shopping, other
}

@Generable
struct LabelFirst {
    @Guide(description: "Verdict for the window the user is looking at")
    var label: Label
    @Guide(description: "How sure you are, 0 to 100", .range(0...100))
    var confidence: Int
    @Guide(description: "At most 14 words explaining the verdict")
    var reason: String
    @Guide(description: "One or two words naming the activity, such as lecture, social media, coding")
    var category: String
    var content_kind: ContentKind
}

@Generable
struct ReasonFirst {
    @Guide(description: "At most 14 words explaining the verdict")
    var reason: String
    @Guide(description: "One or two words naming the activity, such as lecture, social media, coding")
    var category: String
    var content_kind: ContentKind
    @Guide(description: "Verdict for the window the user is looking at")
    var label: Label
    @Guide(description: "How sure you are, 0 to 100", .range(0...100))
    var confidence: Int
}

@Generable
enum Relation {
    case directly_serves, supporting, neutral, unclear, different_activity
}

// Finer-grained than a verdict: the app maps relation -> verdict in code, so policy stays out of the model.
@Generable
struct RelationJudgment {
    @Guide(description: "What the main content of the window is about, at most 10 words")
    var topic: String
    var relation: Relation
    @Guide(description: "At most 14 words explaining the choice")
    var reason: String
}

func emit(_ obj: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
       let s = String(data: data, encoding: .utf8) {
        print(s)
        fflush(stdout)
    }
}

func name(_ l: Label) -> String {
    switch l {
    case .on_task: return "on_task"
    case .unsure: return "unsure"
    case .off_task: return "off_task"
    }
}

func classify(_ error: Error) -> String {
    let d = String(describing: error).lowercased()
    if d.contains("guardrail") { return "guardrail" }
    if d.contains("refus") { return "refusal" }
    if d.contains("context") { return "context_window" }
    return "error"
}

let model = SystemLanguageModel.default
switch model.availability {
case .available:
    emit(["status": "available", "context_size": model.contextSize])
case .unavailable(let reason):
    emit(["status": "unavailable", "reason": String(describing: reason)])
    exit(2)
}

let options = GenerationOptions(sampling: .greedy)

while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = req["id"] as? String,
          let instructions = req["instructions"] as? String,
          let prompt = req["prompt"] as? String else {
        emit(["id": "?", "error": "bad_request"])
        continue
    }
    let order = (req["order"] as? String) ?? "reason-first"
    let session = LanguageModelSession(instructions: instructions)
    do {
        if order == "relation" {
            let r = try await session.respond(to: prompt, generating: RelationJudgment.self, options: options).content
            emit(["id": id, "relation": String(describing: r.relation), "topic": r.topic, "reason": r.reason])
        } else if order == "label-first" {
            let r = try await session.respond(to: prompt, generating: LabelFirst.self, options: options).content
            emit(["id": id, "label": name(r.label), "confidence": r.confidence, "reason": r.reason,
                  "category": r.category, "content_kind": String(describing: r.content_kind)])
        } else {
            let r = try await session.respond(to: prompt, generating: ReasonFirst.self, options: options).content
            emit(["id": id, "label": name(r.label), "confidence": r.confidence, "reason": r.reason,
                  "category": r.category, "content_kind": String(describing: r.content_kind)])
        }
    } catch {
        emit(["id": id, "error": classify(error), "detail": String(describing: error).prefix(200).description])
    }
}
