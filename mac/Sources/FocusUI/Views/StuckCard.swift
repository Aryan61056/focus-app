import SwiftUI

struct StuckCard: View {
    @Bindable var c: SessionController
    @State private var manual = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("One small next step").font(Tokens.rounded(20, .semibold))
                        .help("Suggestions use only your task and project notes. They can miss details; choose what helps.")
                    Spacer()
                    Button { c.cancelNextActions() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Close next steps").help("Close next steps").keyboardShortcut(.cancelAction)
                }
                if c.nextActions.isWorking {
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Finding a starting point on this Mac").font(Tokens.text(14)).foregroundStyle(Tokens.ink2) }
                        .frame(minHeight: 110, alignment: .leading).transition(.opacity)
                } else if let actions = c.nextActions.value {
                    VStack(spacing: 8) {
                        ForEach(actions, id: \.self) { action in
                            Button { c.chooseNextAction(action) } label: {
                                HStack(spacing: 12) { Text(action).multilineTextAlignment(.leading); Spacer(minLength: 8); Image(systemName: "arrow.turn.down.right") }
                                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            }.buttonStyle(FocusButtonStyle(.secondary)).help("Use this as your session goal")
                        }
                    }.transition(.rise(reduce: reduceMotion))
                } else {
                    Text("Focus has no suggestion right now. You can write one small action to try.").font(Tokens.text(14)).foregroundStyle(Tokens.ink2)
                    HStack {
                        TextField("One thing you can do next", text: $manual).textFieldStyle(.roundedBorder).onSubmit(useManual)
                            .accessibilityLabel("Your next action")
                        Button("Use it", action: useManual).disabled(manual.trimmingCharacters(in: .whitespaces).isEmpty)
                    }.transition(.opacity)
                }
            }
        }.motion(Motion.notchSettle, value: c.nextActions)
    }
    private func useManual() { c.changeTask(to: manual) }
}
