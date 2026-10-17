import SwiftUI
import FocusLinkNet

/// Light catching the top edge of a black pill, so it reads as a solid object sitting on the art rather than a hole in it.
enum PillEdge {
    static let gradient = LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03), .clear], startPoint: .top, endPoint: .bottom)
}

/// The picture at the top of a page: the Mac's halftone art with the notch's pill sitting on it. Ripples out once per launch, swells
/// under a finger, and sends a wave out each time `pulse` changes (the session changing state).
struct HeroBanner<Content: View>: View {
    var key: String
    var pattern: HalftonePattern = .hills
    var height: CGFloat = 176
    var pulse = 0
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Halftone(pattern: pattern, ripple: .oncePerLaunch(key), pulse: pulse)
            content.allowsHitTesting(false)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.card + 4, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Metrics.card + 4, style: .continuous).strokeBorder(.white.opacity(0.08)) }
    }
}

/// The notch as it looks right now, as a black capsule: the ring, the task, and the time while a session runs.
struct SessionPill: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let s = model.state
        HStack(spacing: 12) {
            FocusRing(phase: s.isActive ? s.phase : .onTask, progress: nil, lineWidth: 3, onDark: true)
                .frame(width: 24, height: 24).padding(6)
                .background(Circle().fill(.white.opacity(0.08)))
            Text(s.isActive ? s.task : String(localized: "Ready when you are"))
                .font(.system(size: 17, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.interpolate)
            if s.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let t = model.clock.seconds(at: ctx.date).clockText
                    Text(t).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Mint.quiet)
                        .contentTransition(.numericText(countsDown: s.timed)).animation(Motion.settle, value: t)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 8).padding(.trailing, 18)
        .frame(height: 52).frame(maxWidth: 320)
        .background(Capsule().fill(.black))
        .overlay { Capsule().strokeBorder(PillEdge.gradient, lineWidth: 1) }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .padding(.horizontal, 24)
        .motion(Motion.land, value: s.isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.isActive ? s.task : "Ready when you are")
    }
}
