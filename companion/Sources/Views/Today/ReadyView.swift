import SwiftUI

/// Nothing is running. One field, one choice, one button: a returning user starts in a few seconds.
struct ReadyView: View {
    @Environment(AppModel.self) private var model
    @State private var task = ""
    @State private var minutes: Int? = 25
    @State private var started = 0
    @FocusState private var focused: Bool

    private var recentTasks: [String] {
        var seen = Set<String>()
        return (model.displayedInsights?.recent ?? []).map(\.task).filter { seen.insert($0.lowercased()).inserted }.prefix(3).map { $0 }
    }
    private var canStart: Bool { model.connection.isLive && !task.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    FocusRing(phase: .idle, progress: nil, lineWidth: 6).frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready when you are").font(.title2.weight(.semibold))
                        Text(model.connection.isLive ? "Starts on your Mac" : "Waiting for your Mac. Open Focus on it and click Connect your iPhone.")
                            .font(.subheadline).foregroundStyle(Palette.ink2).contentTransition(.interpolate)
                    }
                    Spacer(minLength: 0)
                }
                FocusBar(phase: .idle)
            }
            .padding(.top, 8)
            .reveal(0, key: "today")

            Card {
                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow("What are you working on?")
                    TextField("Calc homework", text: $task, axis: .vertical)
                        .font(.title3.weight(.medium)).lineLimit(1...3)
                        .focused($focused).submitLabel(.go).onSubmit(begin)
                    if !recentTasks.isEmpty && task.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(recentTasks, id: \.self) { t in
                                    Button(t) { withAnimation(Motion.settle) { task = t } }
                                        .font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                                        .padding(.horizontal, 12).frame(minHeight: 36)
                                        .background(Palette.accentSoft, in: .capsule).buttonStyle(PressScale())
                                }
                            }
                        }
                        .scrollIndicators(.hidden).transition(.opacity)
                    }
                    Eyebrow("For how long").padding(.top, 4)
                    ChoiceChips(options: [("Open", nil), ("25 min", 25), ("50 min", 50), ("90 min", 90)], selection: $minutes)
                }
            }
            .reveal(1, key: "today")

            PrimaryButton(title: "Start session", systemImage: "play.fill", action: begin).disabled(!canStart)
                .opacity(canStart ? 1 : 0.55)
                .motion(Motion.settle, value: canStart)
                .reveal(2, key: "today")
            if let n = model.notice { Text(n).font(.footnote).foregroundStyle(Palette.ink2).transition(.opacity) }
        }
        .frame(maxWidth: 520)
        .successFeedback(started)
        .motion(Motion.settle, value: model.notice)
    }

    private func begin() {
        guard canStart else { return }
        focused = false
        model.start(task: task, minutes: minutes)
        started += 1; task = ""
    }
}
