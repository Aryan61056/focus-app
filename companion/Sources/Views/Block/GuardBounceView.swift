import SwiftUI
import FocusLinkNet

/// Where the guard sends you: a calm page that shows the session you started and one clear way back. It never says which app you
/// reached for, and it never scolds.
struct GuardBounceView: View {
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize = 220
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 46

    private var s: SessionState { model.state }
    private var live: Bool { model.connection.isLive }

    var body: some View {
        ZStack {
            Backdrop(phase: s.phase)
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Eyebrow("Still working on")
                    Text(s.task.isEmpty ? "your session" : s.task)
                        .font(.title.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3)
                }
                ring
                Text(live ? "Your session is still running. The app will be there when you're done." : "Can't reach your Mac right now. This is how your session looked last.")
                    .font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    PrimaryButton(title: "Back to task", systemImage: "arrow.uturn.left") {
                        if s.phase == .drifting { model.backToTask() }
                        close()
                    }
                    Button("Take a break instead") { takeBreak() }
                        .font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink2).frame(minHeight: 44)
                    if let n = model.notice { Text(n).font(.footnote).foregroundStyle(Palette.ink2).transition(.opacity) }
                }
            }
            .padding(.horizontal, Metrics.gutter).padding(.bottom, 12)
            .frame(maxWidth: 520)
        }
        .tapFeedback(model.guardCount)
        .motion(Motion.settle, value: model.notice)
        .interactiveDismissDisabled(false)
    }

    private var ring: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let seconds = model.clock.seconds(at: ctx.date)
            let remaining = model.clock.progress(at: ctx.date).map { max(0.02, 1 - $0) }
            ZStack {
                FocusRing(phase: s.phase, progress: remaining, lineWidth: 12)
                VStack(spacing: 2) {
                    Text(seconds.clockText)
                        .font(.system(size: clockSize, weight: .semibold, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(s.timed ? "left" : "elapsed").font(.subheadline).foregroundStyle(Palette.ink2)
                }
                .padding(30)
            }
            .frame(width: ringSize, height: ringSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(s.task), \(seconds.spokenText) \(s.timed ? "left" : "elapsed")")
        }
    }

    private func close() { model.showingGuard = false }

    private func takeBreak() {
        guard live else { return model.show("Your Mac isn't connected, so it can't start the break.") }
        model.takeBreak()
        close()
    }
}
