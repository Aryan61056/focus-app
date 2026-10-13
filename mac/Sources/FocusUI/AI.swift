import Foundation
import FocusJudge

/// A piece of model-written text on its way: nothing yet, working, ready, or the model could not help (shown as nothing).
public enum AIState<Value: Equatable & Sendable>: Equatable, Sendable {
    case idle, working, ready(Value), failed
    public var value: Value? { if case .ready(let v) = self { return v }; return nil }
    public var isWorking: Bool { if case .working = self { return true }; return false }
}

extension SessionController {
    /// Whether AI text can be offered now: the user allows it, the model is switched on, and macOS has not said it is unavailable.
    public var aiAvailable: Bool {
        if case .unavailable = judgeStatus { return false }
        return prefs.aiHelp && prefs.useModel
    }

    // MARK: facts

    /// What the model may know about the session. Counts and times always; window text only for Ask Focus, which the user opens.
    func sessionFacts(includeWindows: Bool) -> String {
        var lines = ["Task: \(taskName)"]
        if let p = projectForNote, !p.context.isEmpty { lines.append("Project notes: \(p.context)") }
        if let s = summary {
            lines.append("Time on task: \(Int((max(0, s.activeSeconds - s.offTopicSeconds - s.unsureSeconds) / 60).rounded())) minutes of \(Int((s.activeSeconds / 60).rounded())) active minutes")
            lines.append("Slips noticed: \(s.drifts). Nudges shown: \(s.interrupts). Not sure: \(Int((s.unsureSeconds / 60).rounded())) minutes.")
        } else if isActive {
            lines.append("Session is still running.")
        }
        lines.append("Readings this session: \(stats.total) (on task \(stats.onTask), not sure \(stats.unsure), off topic \(stats.offTask))")
        if includeWindows {
            for r in readings.reversed().suffix(24) where r.source != .sensitive {
                let label = r.call == .on ? "on task" : (r.call == .off ? "off topic" : "not sure")
                let t = r.date.formatted(.dateTime.hour().minute())
                lines.append("\(t) | \(r.appText) | \(String(r.titleText.prefix(80))) | \(label) | \(String(r.reason.prefix(100)))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: recap

    func startRecap() {
        recapTask?.cancel()
        guard aiAvailable, summary != nil else { recap = .idle; return }
        recap = .working
        let facts = sessionFacts(includeWindows: false), assistant = self.assistant
        recapTask = Task { [weak self] in
            let r = await assistant.recap(facts: facts)
            guard !Task.isCancelled else { return }
            self?.recap = r.map { .ready($0) } ?? .failed
        }
    }

    // MARK: ask

    /// One question, one answer. Nothing is kept between questions.
    public func askFocus(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, aiAvailable, !answer.isWorking else { return }
        answer = .working
        let facts = sessionFacts(includeWindows: true), assistant = self.assistant
        Task { [weak self] in
            let a = await assistant.answer(question: q, facts: facts)
            self?.answer = a.map { .ready($0) } ?? .failed
        }
    }

    public func clearAnswer() { answer = .idle }

    // MARK: task coach

    /// Suggest a clearer task and a line about what counts. Nothing changes until the user accepts.
    public func sharpenTask(_ task: String) {
        let t = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 3, aiAvailable, !sharpened.isWorking else { return }
        sharpened = .working
        let ctx = store?.projects.first { $0.name.caseInsensitiveCompare(t) == .orderedSame }?.context ?? ""
        let assistant = self.assistant
        Task { [weak self] in
            let s = await assistant.sharpen(task: t, context: ctx)
            self?.sharpened = s.map { .ready($0) } ?? .failed
        }
    }

    public func clearSharpened() { sharpened = .idle }

    /// Accepting a suggestion saves its "what counts" line on the project, only if the project has no description yet.
    public func saveContextIfEmpty(task: String, context: String) {
        let c = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let store, !c.isEmpty else { return }
        var p = store.projectNamed(task)
        guard p.context.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        p.context = String(c.prefix(400)); store.update(p)
    }
}
