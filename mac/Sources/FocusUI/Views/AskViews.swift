import SwiftUI
import FocusJudge

/// Ask the model about this session. One question, one answer, nothing kept. It may name windows because the user is asking.
struct AskPanel: View {
    @Bindable var c: SessionController
    /// In the Focus panel: no heading (the panel has one) and the suggestions wrap.
    var compact = false
    @State private var question = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Space.s) {
                if !compact {
                    HStack(spacing: Space.s) {
                        Text("Ask Focus").font(Tokens.text(.callout, .semibold)).accessibilityAddTraits(.isHeader)
                        AITag()
                        Spacer()
                    }
                }
                // The button beside the field when there is room for both; under it, at the right, when the panel is narrow, so the
                // field's hint is never cut off.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.xs) { field.frame(minWidth: 160 * TextScale.shared.factor); askButton() }
                    VStack(spacing: Space.xs) { field; askButton(fill: true) }
                }
                if case .idle = c.answer {
                    FlowRow(spacing: Space.xs) {
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
                    .modifier(CardSurface())
                    .accessibilityElement(children: .combine)
                case .idle: EmptyView()
                }
            }
        }
    }

    var field: some View {
        TextField(compact ? "Ask about this session" : "Why did you flag that window?", text: $question).font(Tokens.text(.callout))
            .wellField(focused: focused)
            .focused($focused).onSubmit(ask)
    }
    func askButton(fill: Bool = false) -> some View {
        Button { ask() } label: { Text("Ask").frame(maxWidth: fill ? .infinity : nil) }
            .buttonStyle(FocusButtonStyle(.secondary)).disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || c.answer.isWorking)
    }

    func ask() { c.askFocus(question) }

    func chip(_ text: String) -> some View {
        Button(text) { question = text; ask() }.buttonStyle(ChoiceStyle(on: false))
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
            // Inside the finished-session card, so a well (the card's own white would make it vanish in light mode).
            .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
        }
    }
}
