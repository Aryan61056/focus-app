import SwiftUI
import FocusJudge

/// Ask the model about this session. One question, one answer, nothing kept. It may name windows because the user is asking.
struct AskPanel: View {
    @Bindable var c: SessionController
    @State private var question = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("Ask Focus").font(Tokens.text(14, .semibold)).accessibilityAddTraits(.isHeader)
                    AITag()
                    Spacer()
                }
                HStack(spacing: 8) {
                    TextField("Why did you flag that window?", text: $question).textFieldStyle(.plain).font(Tokens.text(14))
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: Tokens.radiusControl).fill(Tokens.control))
                        .focused($focused).onSubmit(ask)
                    Button("Ask") { ask() }.buttonStyle(FocusButtonStyle(.secondary)).disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || c.answer.isWorking)
                }
                if case .idle = c.answer {
                    HStack(spacing: 6) {
                        chip("What pulled me away?")
                        chip("Why was I flagged?")
                        chip("Which windows helped?")
                    }
                }
                switch c.answer {
                case .working:
                    HStack(spacing: 8) { ThinkingDot(); Text("Reading this session's notes on this Mac").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
                case .failed:
                    Text("Focus could not answer that. Try rephrasing it, or open All readings above.").font(Tokens.text(13)).foregroundStyle(Tokens.ink2)
                case .ready(let a):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(a).font(Tokens.text(14)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Button("Clear") { c.clearAnswer(); question = "" }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.window2))
                    .accessibilityElement(children: .combine)
                case .idle: EmptyView()
                }
            }
        }
    }

    func ask() { c.askFocus(question) }

    func chip(_ text: String) -> some View {
        Button(text) { question = text; ask() }.buttonStyle(.plain).font(Tokens.text(12.5, .medium))
            .padding(.horizontal, 12).frame(height: 28).background(Capsule().fill(Tokens.control))
    }
}

/// After a session: two plain sentences from the model, with a next step you can take or ignore. Names no site or app.
struct RecapBlock: View {
    @Bindable var c: SessionController
    var body: some View {
        switch c.recap {
        case .idle, .failed: EmptyView()
        case .working:
            HStack(spacing: 8) { ThinkingDot(); Text("Writing a short recap on this Mac").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
        case .ready(let r):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) { Text("Recap").font(Tokens.text(13, .semibold)); AITag() }
                Text(r.summary).font(Tokens.text(14)).fixedSize(horizontal: false, vertical: true)
                if !r.nextStep.isEmpty, let p = c.projectForNote, p.nextStep.isEmpty {
                    HStack(spacing: 8) {
                        Text("Suggested next step: \(r.nextStep)").font(Tokens.text(13)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                        Button("Use it") { c.setProjectNextStep(r.nextStep) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.window2))
        }
    }
}
