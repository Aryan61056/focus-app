import SwiftUI
import FocusLinkNet

/// A session is running on the Mac. The ring and clock are the whole screen; controls stay out of the way until you need them.
struct ActiveSessionView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEnd = false
    @State private var sent = 0
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize = 272
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 56

    private var s: SessionState { model.state }
    private var live: Bool { model.connection.isLive }

    var body: some View {
        VStack(spacing: 26) {
            FocusBar(phase: s.phase).reveal(0, key: "active")
            VStack(spacing: 4) {
                Eyebrow("Working on")
                Text(s.task).font(.title2.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3)
            }
            .reveal(0, key: "active")

            ringAndClock.reveal(1, key: "active")
            status.reveal(2, key: "active")
            Text("Hushd can be wrong. When it isn't sure, it does nothing.").font(.footnote).foregroundStyle(Palette.ink2).multilineTextAlignment(.center).reveal(2, key: "active")
            controls.reveal(3, key: "active")
            Button("End session", role: .destructive) { confirmEnd = true }
                .font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink2).frame(minHeight: 44)
                .reveal(4, key: "active")
        }
        .frame(maxWidth: 520)
        .opacity(live ? 1 : 0.55)
        .overlay(alignment: .top) { if !live { OfflineBanner().transition(.move(edge: .top).combined(with: .opacity)) } }
        .motion(Motion.settle, value: live)
        .tapFeedback(sent)
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End session", role: .destructive) { sent += 1; model.end() }
            Button("Keep going", role: .cancel) {}
        } message: { Text("It's saved to your history.") }
    }

    private var ringAndClock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let seconds = model.clock.seconds(at: ctx.date)
            // A timed ring starts full and runs down, like the system Timer; an open one stays closed.
            let remaining = model.clock.progress(at: ctx.date).map { max(0.02, 1 - $0) }
            ZStack {
                FocusRing(phase: s.phase, progress: remaining, lineWidth: 14)
                VStack(spacing: 2) {
                    Text(seconds.clockText)
                        .font(.system(size: clockSize, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(countsDown: s.timed)).minimumScaleFactor(0.6).lineLimit(1)
                        .animation(Motion.settle, value: seconds.clockText)
                    Text(s.timed ? "left" : "elapsed").font(.subheadline).foregroundStyle(Palette.ink2)
                }
                .padding(36)
            }
            .frame(width: ringSize, height: ringSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(s.task), \(seconds.spokenText) \(s.timed ? "left" : "elapsed"), \(s.phase.accessibleName)")
        }
    }

    private var status: some View {
        VStack(spacing: 8) {
            Label(s.phase.label, systemImage: s.phase.symbol)
                .font(.headline).foregroundStyle(s.phase.tint).symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace)).labelStyle(.titleAndIcon)
            if s.phase == .drifting {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text("Away for \(model.clock.offTopicSeconds(at: ctx.date).clockText)").font(.subheadline.monospacedDigit()).foregroundStyle(Palette.drift)
                }
            }
            if let d = s.phase.detail(task: s.task) {
                Text(d).font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center).transition(.opacity)
            }
            if let note = s.note { Text(note).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink).transition(.opacity) }
            if model.blocker.shielding {
                Label("\(model.blocker.count) covered", systemImage: "shield.lefthalf.filled")
                    .font(.footnote.weight(.medium)).foregroundStyle(Palette.ink2).transition(.opacity)
            }
            if let n = model.notice { Text(n).font(.footnote).foregroundStyle(Palette.ink2).transition(.opacity) }
        }
        .frame(minHeight: 72, alignment: .top)
        .motion(Motion.settle, value: s.phase)
        .motion(Motion.settle, value: s.note)
        .motion(Motion.settle, value: model.blocker.shielding)
        .motion(Motion.settle, value: model.notice)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if s.phase == .drifting {
                PrimaryButton(title: "Back to task", systemImage: "arrow.uturn.left") { sent += 1; model.backToTask() }
            } else if s.phase == .paused || s.phase == .onBreak {
                PrimaryButton(title: "Resume", systemImage: "play.fill") { sent += 1; model.resume() }
            }
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    if s.phase != .paused && s.phase != .onBreak {
                        SoftButton(title: "Pause", systemImage: "pause.fill") { sent += 1; model.pause() }
                        SoftButton(title: "Break", systemImage: "cup.and.saucer.fill") { sent += 1; model.takeBreak() }
                    }
                    if s.timed { SoftButton(title: "+5 min", systemImage: "plus") { sent += 1; model.extend(minutes: 5) } }
                }
            }
        }
        .disabled(!live)
        .motion(Motion.land, value: s.phase)
    }
}

private struct OfflineBanner: View {
    var body: some View {
        Label("Reconnecting to your Mac", systemImage: "wifi.exclamationmark")
            .font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
            .padding(.horizontal, 14).padding(.vertical, 8).glassEffect(.regular, in: .capsule)
    }
}

extension SessionState.Phase {
    var accessibleName: String {
        switch self {
        case .idle: "ready"
        case .onTask: "on task"
        case .unsure: "not sure"
        case .drifting: "drifting"
        case .recovering: "getting back on task"
        case .paused: "paused"
        case .onBreak: "on a break"
        }
    }
}
