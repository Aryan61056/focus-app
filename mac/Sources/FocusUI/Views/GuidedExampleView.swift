import SwiftUI

public struct GuidedExampleView: View {
    @Bindable var example: GuidedExample
    var close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(example: GuidedExample, close: @escaping () -> Void) { self.example = example; self.close = close }
    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("An example, using made-up windows", systemImage: "play.rectangle").font(Tokens.text(13, .semibold)).foregroundStyle(Tokens.ink2)
                Spacer()
                Button("Done", action: close).keyboardShortcut(.cancelAction).help("Close the example")
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(GuidedExample.titles[example.step]).font(Tokens.rounded(28, .semibold)).contentTransition(.opacity)
                    Text(GuidedExample.explanations[example.step]).font(Tokens.text(14)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("\(example.step + 1) of 4").font(Tokens.text(13)).monospacedDigit().contentTransition(.numericText())
            }.frame(minHeight: 100, alignment: .top)
            HStack(spacing: 14) {
                LiveRing(example.controller.ringState, color: example.controller.ringColor).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(example.controller.taskName).font(Tokens.rounded(20, .semibold))
                    Text(example.controller.presenceLabel).font(Tokens.text(13)).foregroundStyle(Tokens.ink2)
                }
                Spacer()
                if example.preparing { ProgressView().controlSize(.small).accessibilityLabel("Preparing the example") }
            }.frame(height: 60)
            ScrollView {
                SeeingCard(c: example.controller, showPreview: false, isExample: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button("Back") { example.select(example.step - 1) }.disabled(example.step == 0).keyboardShortcut(.leftArrow, modifiers: [])
                Spacer()
                Button(example.playing ? "Pause playback" : "Autoplay") { example.playing ? example.pause() : example.autoplay() }
                    .help("Play the four example scenes in about 90 seconds")
                Button(example.step == 3 ? "Replay" : "Next") { example.select(example.step == 3 ? 0 : example.step + 1) }
                    .buttonStyle(FocusButtonStyle(.primary)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(minWidth: 700, idealWidth: 780, minHeight: 650)
        .background(Tokens.window)
        .motion(Motion.notchSettle, value: example.step)
        .onDisappear { example.stop(); close() }
    }
}
