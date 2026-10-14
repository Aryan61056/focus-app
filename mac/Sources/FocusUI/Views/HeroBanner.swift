import SwiftUI

/// The picture at the top of a page, the way Droppy heads its pages: artwork with a live copy of the notch on it, and a caption.
struct HeroBanner<Inset: View>: View {
    var caption: String
    @ViewBuilder var inset: Inset
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                HeroArtwork()
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

/// Halftone hills in the app's green under a deep sky with a few stars: drawn here, so nothing ships as an image.
struct HeroArtwork: View {
    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.03, green: 0.22, blue: 0.16), Color(red: 0.05, green: 0.40, blue: 0.27), Color(red: 0.10, green: 0.55, blue: 0.36)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width * 0.4, y: size.height)))
            // Dots grow where the "hills" are, which gives the printed look without an image.
            let step: CGFloat = 4
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let u = x / size.width, v = y / size.height
                    let hill1 = v - (0.72 - 0.18 * sin(u * 5.2 + 0.6) - 0.06 * sin(u * 13))
                    let hill2 = v - (0.38 + 0.22 * cos(u * 3.4 + 1.9) + 0.05 * sin(u * 17 + 2))
                    // Soft edges: dots are biggest on the crest of each hill and thin out away from it, like printed clouds.
                    let crest1 = max(0, 1 - abs(hill1) * 4.5), crest2 = max(0, 1 - abs(hill2) * 5)
                    let cloud = crest1 * crest1 * 1.1 + crest2 * crest2 * 0.9 + (hill1 > 0 ? 0.3 + 0.25 * sin(u * 40 + v * 23) * sin(u * 11) : 0)
                    let r = min(3.2, cloud * 3.0)
                    if r > 0.35 {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)), with: .color(.white.opacity(0.22 + 0.5 * min(1, cloud))))
                    }
                    x += step
                }
                y += step
            }
            for (i, star) in [(0.12, 0.2), (0.31, 0.12), (0.58, 0.18), (0.82, 0.1), (0.9, 0.34), (0.44, 0.07), (0.7, 0.28)].enumerated() {
                let r: CGFloat = i % 3 == 0 ? 1.6 : 1
                ctx.fill(Path(ellipseIn: CGRect(x: star.0 * size.width, y: star.1 * size.height, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.7)))
            }
        }
        .accessibilityHidden(true)
    }
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
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
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
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .motion(Motion.notchSettle, value: text)
        .accessibilityElement(children: .combine)
    }
}
