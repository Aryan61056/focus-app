import SwiftUI
import FocusLinkNet

/// The session ring. State is carried by shape so it reads without color: a closed ring when on task, dots when unsure,
/// a ring with a gap when drifting, dashes when paused. The same vocabulary as the Mac app's menu bar ring.
struct FocusRing: View {
    var phase: SessionState.Phase
    /// 0...1 for a timed session; nil for an open one (the ring is simply complete).
    var progress: Double?
    var lineWidth: CGFloat = 14

    private var look: Look {
        let accent = Palette.accent, quiet = Palette.ink2
        switch phase {
        case .idle: return Look(trim: 1, dash: [1, 0], color: Palette.track)
        case .onTask, .recovering: return Look(trim: max(0.015, progress ?? 1), dash: [1, 0], color: accent)
        case .unsure: return Look(trim: 1, dash: [0.01, 2.2], color: quiet)
        case .drifting: return Look(trim: 0.8, dash: [1, 0], color: Palette.drift)
        case .paused, .onBreak: return Look(trim: 1, dash: [3, 2.4], color: quiet)
        }
    }

    private struct Look: Equatable { var trim: Double; var dash: [CGFloat]; var color: Color }

    var body: some View {
        let look = look
        ZStack {
            Circle().stroke(Palette.track.opacity(look.dash == [1, 0] ? 1 : 0.35), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: look.trim)
                .stroke(look.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: look.dash.map { $0 * lineWidth }.map { max($0, 0.01) }))
                .rotationEffect(.degrees(-90 + (phase == .drifting ? 36 : 0)))
        }
        .motion(Motion.follow, value: phase)
        .motion(Motion.follow, value: progress)
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

#Preview("States") {
    ScrollView(.horizontal) {
        HStack(spacing: 24) {
            ForEach([SessionState.Phase.idle, .onTask, .unsure, .drifting, .paused], id: \.self) { p in
                FocusRing(phase: p, progress: p == .onTask ? 0.6 : nil).frame(width: 120, height: 120)
            }
        }.padding()
    }
}
