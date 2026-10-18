import SwiftUI
import FocusJudge

/// Head of Today between sessions, in place of a picture. As you type a task, the on-device model works out what will count as on task
/// and shows it here, before anything starts, so you can see (and correct) what Focus will compare windows with. With a project that
/// already has notes it shows those instead and asks the model nothing. Nothing leaves this Mac and nothing changes until you press "Use this".
struct FocusPreviewCard: View {
    @Bindable var c: SessionController
    /// The task text the last request was made for, so a late answer for older text is never shown against newer text.
    @State private var askedFor = ""
    /// A suggestion the person turned down for this text; the card stops asking until the text changes.
    @State private var skipped = ""

    private var parsed: (task: String, minutes: Int?) { StartSheet.parse(c.startDraft.task) }
    private var task: String { parsed.task }
    /// The project Return would start: the one named, or with nothing typed the one worked on last.
    private var project: Project? {
        task.isEmpty ? StartSheet.lastProject(c.store) : ProjectMatch.exact(task, in: c.store?.projects ?? [])
    }
    private var notes: String? {
        guard let text = project?.context.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    private var accepted: Sharpened? { c.startDraft.accepted?.task == task ? c.startDraft.accepted : nil }
    /// Worth asking the model: a real task, nothing said about it yet, nothing already chosen or turned down.
    private var canSuggest: Bool {
        task.count >= 3 && c.aiAvailable && notes == nil && accepted == nil && skipped != task
    }

    var body: some View {
        Tile(padding: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    Image(systemName: "sparkles").font(Tokens.symbol(13, .semibold)).foregroundStyle(Tokens.accent).accessibilityHidden(true)
                    Text("What Focus will look for").font(Tokens.text(.callout, .semibold)).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    if showsAIText { AITag() }
                }
                content
                Text("Focus can be wrong. When it isn\u{2019}t sure, it does nothing.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .motion(Motion.notchSettle, value: c.sharpened)
        .motion(Motion.notchSettle, value: accepted)
        .task(id: task) {
            guard canSuggest else { return }
            // Wait for a pause in typing so the model is asked about a finished thought, not every letter.
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, canSuggest, !c.sharpened.isWorking else { return }
            askedFor = task
            c.sharpenTask(task)
        }
    }

    private var showsAIText: Bool {
        if accepted != nil { return true }
        if case .ready = c.sharpened, askedFor == task, canSuggest { return true }
        return false
    }

    @ViewBuilder private var content: some View {
        if let accepted {
            counts(accepted.counts, label: "Counts as on task", footnote: "Saved with the project when you start.")
        } else if let notes, let project {
            counts(notes, label: "From your notes on \(project.name)", footnote: nil)
            Button("Edit under Projects") { c.requestSection(.projects) }.buttonStyle(FocusButtonStyle(.plain, small: true))
        } else if canSuggest {
            switch c.sharpened {
            case .working:
                HStack(spacing: Space.xs) { ThinkingDot(); Text("Working out what counts, on this Mac").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
            case .ready(let s) where askedFor == task: suggestion(s)
            case .failed where askedFor == task:
                Text("No suggestion right now. Focus will compare windows with your task as you typed it.").font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2)
            default: reads
            }
        } else {
            reads
        }
    }

    /// What Focus compares with the task. The idle state: nothing typed yet, or nothing the model can add.
    private var reads: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            FlowRow(spacing: Space.xs) {
                check("macwindow", "App in front")
                check("textformat", "Window title")
                check("doc.text.magnifyingglass", "Page or file")
            }
            if c.aiAvailable, task.count < 3 {
                Text("Type a task and Focus says what will count.").font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2)
            }
        }
    }

    private func check(_ symbol: String, _ label: String) -> some View {
        Label(label, systemImage: symbol).font(Tokens.text(.caption, .medium)).foregroundStyle(Tokens.ink2)
            .padding(.horizontal, Space.s).frame(height: 26)
            .background(Capsule().fill(Tokens.well))
    }

    private func counts(_ text: String, label: String, footnote: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).font(Tokens.text(.caption, .medium)).foregroundStyle(Tokens.ink2)
            Text(text).font(Tokens.text(.callout)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let footnote { Text(footnote).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
        }
    }

    private func suggestion(_ s: Sharpened) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Inset {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(s.task).font(Tokens.text(.callout, .semibold))
                    if !s.counts.isEmpty {
                        Text("Counts as on task: \(s.counts)").font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: Space.xs) {
                Button("Use this") {
                    c.startDraft.task = s.task
                    c.startDraft.accepted = s
                    c.clearSharpened()
                }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                Button("Keep mine") { skipped = task; c.clearSharpened() }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        }
    }
}
