import SwiftUI

/// The picture at the top of a page, the way Droppy heads its pages: artwork with a live copy of the notch on it, and a caption.
/// `pulse` is anything that changes when the notch's state does; each change sends a soft wave out through the dots from the notch.
struct HeroBanner<Inset: View>: View {
    var caption: String
    var pulse: Int = 0
    @ViewBuilder var inset: Inset
    var body: some View {
        VStack(spacing: Space.xs) {
            ZStack {
                HeroArtwork(pulse: pulse)
                inset
            }
            .frame(height: 176)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).strokeBorder(Color.white.opacity(0.08)) }
            Text(caption).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Halftone hills in the app's green under a deep sky with a few stars: drawn here, so nothing ships as an image. It moves the way the
/// website's art does (see `Halftone`): a ripple out from the notch once per launch, a swell under the pointer, a wave on state change.
struct HeroArtwork: View {
    var pulse = 0
    var body: some View { Halftone(pattern: .hills, ripple: .oncePerLaunch("hero"), pulse: pulse) }
}

/// The notch as it looks right now, as a black capsule: ring, task and time while a session runs.
struct NotchPreviewPill: View {
    @Bindable var c: SessionController
    var body: some View {
        TimelineView(.everySecond) { _ in
            HStack(spacing: Space.s) {
                LiveRing(c.isActive ? c.ringState : .on, color: c.isActive && c.ringColor == Tokens.accent ? NotchView.accent : NotchView.ink)
                    .frame(width: 22, height: 22)
                    .padding(Space.xs)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                Text(c.isActive ? c.taskName : "Ready when you are").font(Tokens.fixed(.headline, .semibold)).lineLimit(1).frame(maxWidth: 190, alignment: .leading)
                    .contentTransition(.interpolate).motion(Motion.notchSettle, value: c.isActive ? c.taskName : "")
                Spacer(minLength: 8)
                if c.isActive {
                    Text(c.clockText()).font(Tokens.fixed(.headline, .semibold, rounded: true)).monospacedDigit().foregroundStyle(NotchView.ink2)
                }
            }
            .foregroundStyle(NotchView.ink)
            .padding(.leading, Space.xs).padding(.trailing, Space.l)
            .frame(width: 300, height: 52)
            .background(Capsule().fill(.black))
            .overlay { Capsule().strokeBorder(PillEdge.gradient, lineWidth: 1) }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .motion(Motion.notchOpen, value: c.isActive)
    }
}

/// Light catching the top edge of a black pill, so it reads as a solid object sitting on the art.
enum PillEdge {
    static let gradient = LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03), .clear], startPoint: .top, endPoint: .bottom)
}

/// A slimmer banner for a page: the same halftone art with the one number the page is about on a black pill, so each page says where
/// you are at a glance. The ripple plays once per launch, so coming back to a page is quiet.
struct PageBanner: View {
    var key: String
    var symbol: String
    var text: String
    var detail: String?
    var phase: Double
    var body: some View {
        ZStack {
            Halftone(pattern: .ridge(phase: phase), ripple: .oncePerLaunch(key))
            HStack(spacing: Space.s) {
                Image(systemName: symbol).font(Tokens.symbol(15, .semibold)).foregroundStyle(NotchView.accent)
                    .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.08)))
                Text(text).font(Tokens.text(.headline, .semibold)).foregroundStyle(NotchView.ink).contentTransition(.interpolate)
                if let detail {
                    Text(detail).font(Tokens.text(.callout, .medium)).foregroundStyle(NotchView.ink2).lineLimit(1)
                }
            }
            .padding(.leading, Space.xs).padding(.trailing, Space.l).frame(height: 52)
            .background(Capsule().fill(.black))
            .overlay { Capsule().strokeBorder(PillEdge.gradient, lineWidth: 1) }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .motion(Motion.notchSettle, value: text)
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).strokeBorder(Color.white.opacity(0.08)) }
        .accessibilityElement(children: .combine)
    }
}
