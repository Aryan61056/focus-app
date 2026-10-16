import SwiftUI

/// The picture at the top of a page, the way Droppy heads its pages: artwork with a live copy of the notch on it, and a caption.
/// `pulse` is anything that changes when the notch's state does; each change sends a soft wave out through the dots from the notch.
struct HeroBanner<Inset: View>: View {
    var caption: String
    var pulse: Int = 0
    @ViewBuilder var inset: Inset
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                HeroArtwork(pulse: pulse)
                inset
            }
            .frame(height: 176)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08)) }
            Text(caption).font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Halftone hills in the app's green under a deep sky with a few stars: drawn here, so nothing ships as an image. It moves the way the
/// website's art does (see `Halftone`): a ripple out from the notch once per launch, a swell under the pointer, a wave on a state change.
struct HeroArtwork: View {
    var pulse = 0
    var body: some View { Halftone(pattern: .hills, ripple: .oncePerLaunch("hero"), pulse: pulse) }
}

/// The notch as it looks right now, as a black capsule: ring, task and time while a session runs.
struct NotchPreviewPill: View {
    @Bindable var c: SessionController
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 12) {
                LiveRing(c.isActive ? c.ringState : .on, color: c.isActive && c.ringColor == Tokens.accent ? NotchView.accent : NotchView.ink)
                    .frame(width: 22, height: 22)
                    .padding(6)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                Text(c.isActive ? c.taskName : "Ready when you are").font(Tokens.text(17, .semibold)).lineLimit(1).frame(maxWidth: 190, alignment: .leading)
                    .contentTransition(.interpolate).motion(Motion.notchSettle, value: c.isActive ? c.taskName : "")
                Spacer(minLength: 8)
                if c.isActive {
                    let t = c.clockText()
                    Text(t).font(Tokens.rounded(17, .semibold)).monospacedDigit().foregroundStyle(NotchView.ink2)
                        .contentTransition(.numericText(countsDown: c.mode == .timed)).motion(Motion.out(0.3), value: t)
                }
            }
            .foregroundStyle(NotchView.ink)
            .padding(.leading, 8).padding(.trailing, 18)
            .frame(width: 300, height: 52)
            .background(Capsule().fill(.black))
            .overlay { Capsule().strokeBorder(PillEdge.gradient, lineWidth: 1) }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .motion(Motion.notchOpen, value: c.isActive)
    }
}

/// A nudge as the notch shows it, for the Nudges page: the words and the one way forward. It only shows; nothing here is a button.
struct NudgePreviewPill: View {
    var text: String
    var body: some View {
        HStack(spacing: 14) {
            Text(text).font(Tokens.rounded(16, .semibold)).foregroundStyle(NotchView.ink).lineLimit(1)
                .contentTransition(.interpolate)
            Text("Back to task").font(Tokens.text(12.5, .semibold)).foregroundStyle(Color(red: 0.02, green: 0.1, blue: 0.05))
                .padding(.horizontal, 14).frame(height: 28).background(Capsule().fill(NotchView.accent))
        }
        .padding(.leading, 22).padding(.trailing, 10)
        .frame(height: 52)
        .background(Capsule().fill(.black))
        .overlay { Capsule().strokeBorder(PillEdge.gradient, lineWidth: 1) }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .motion(Motion.notchSettle, value: text)
        .accessibilityElement(children: .combine)
    }
}

/// Light catching the top edge of a black pill, so it reads as a solid object sitting on the art rather than a hole in it.
enum PillEdge {
    static let gradient = LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03), .clear], startPoint: .top, endPoint: .bottom)
}
