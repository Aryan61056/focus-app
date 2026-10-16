import SwiftUI
import FocusJudge

/// Ask the model about this session. One question, one answer, nothing kept. It may name windows because the user is asking.
struct AskPanel: View {
    @Bindable var c: SessionController
    @State private var question = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    Text("Ask Focus").font(Tokens.text(.callout, .semibold)).accessibilityAddTraits(.isHeader)
                    AITag()
                    Spacer()
                }
                HStack(spacing: Space.xs) {
                    TextField("Why did you flag that window?", text: $question).textFieldStyle(.plain).font(Tokens.text(.callout))
                        .padding(.horizontal, Space.s).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: Tokens.radiusControl).fill(Tokens.control))
                        .focused($focused).onSubmit(ask)
                    Button("Ask") { ask() }.buttonStyle(FocusButtonStyle(.secondary)).disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || c.answer.isWorking)
                }
                if case .idle = c.answer {
                    HStack(spacing: Space.xs) {
                        chip("What pulled me away?")
                        chip("Why was I flagged?")
                        chip("Which windows helped?")
                    }
                }
                switch c.answer {
                case .working:
                    HStack(spacing: Space.xs) { ThinkingDot(); Text("Reading this session's notes on this Mac").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
                case .failed:
                    Text("Focus could not answer that. Try rephrasing it, or open All readings above.").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                case .ready(let a):
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(a).font(Tokens.text(.callout)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Button("Clear") { c.clearAnswer(); question = "" }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                    .padding(Space.m).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Tokens.radiusInset).fill(Tokens.window2))
                    .accessibilityElement(children: .combine)
                case .idle: EmptyView()
                }
            }
        }
    }

    func ask() { c.askFocus(question) }

    func chip(_ text: String) -> some View {
        Button(text) { question = text; ask() }.buttonStyle(.plain).font(Tokens.text(.caption, .medium))
            .padding(.horizontal, Space.s).frame(height: 28).background(Capsule().fill(Tokens.control))
    }
}

/// After a session: two plain sentences from the model, with a next step you can take or ignore. Names no site or app.
struct RecapBlock: View {
    @Bindable var c: SessionController
    var body: some View {
        switch c.recap {
        case .idle, .failed: EmptyView()
        case .working:
            HStack(spacing: Space.xs) { ThinkingDot(); Text("Writing a short recap on this Mac").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
        case .ready(let r):
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) { Text("Recap").font(Tokens.text(.body, .semibold)); AITag() }
                Text(r.summary).font(Tokens.text(.callout)).fixedSize(horizontal: false, vertical: true)
                if !r.nextStep.isEmpty, let p = c.projectForNote, p.nextStep.isEmpty {
                    HStack(spacing: Space.xs) {
                        Text("Suggested next step: \(r.nextStep)").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                        Button("Use it") { c.setProjectNextStep(r.nextStep) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                }
            }
            .padding(Space.m).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusInset).fill(Tokens.window2))
        }
    }
}
