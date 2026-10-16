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

/// Halftone hills in the app's green under a deep sky with a few stars: drawn here, so nothing ships as an image.
/// It moves the way the website's art does: the dots ripple in from the notch the first time it shows after launch, swell softly
/// under the pointer (the swell trails the pointer as if it had weight), and a wave runs out from the notch when its state changes.
/// Nothing redraws while nothing moves. Reduce Motion draws it still.
struct HeroArtwork: View {
    var pulse = 0
    @State private var field = HalftoneField()
    @State private var live = false
    @State private var pointer: CGPoint?
    @State private var sleep: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !live || reduceMotion)) { timeline in
            Canvas { ctx, size in
                field.draw(&ctx, size: size, now: timeline.date.timeIntervalSinceReferenceDate, pointer: pointer, still: reduceMotion)
            }
        }
        .onContinuousHover { phase in
            guard !reduceMotion else { return }
            switch phase {
            case .active(let p): pointer = p; wake(for: 1.2)
            case .ended: pointer = nil; wake(for: 1.2)
            }
        }
        .onAppear {
            guard !reduceMotion, !HalftoneField.rippled else { return }
            HalftoneField.rippled = true
            field.ripple(at: Date.now.timeIntervalSinceReferenceDate); wake(for: 2.4)
        }
        .onChange(of: pulse) { _, _ in
            guard !reduceMotion else { return }
            field.pulse(at: Date.now.timeIntervalSinceReferenceDate); wake(for: HalftoneField.pulseLife + 0.2)
        }
        .onDisappear { sleep?.cancel(); live = false }
        .accessibilityHidden(true)
    }

    /// Runs the frame clock for a while, then lets it stop once everything has settled.
    private func wake(for seconds: Double) {
        live = true
        field.awakeUntil = max(field.awakeUntil, Date.now.timeIntervalSinceReferenceDate + seconds)
        sleep?.cancel()
        sleep = Task { @MainActor in
            while !Task.isCancelled {
                let left = field.awakeUntil - Date.now.timeIntervalSinceReferenceDate
                if left <= 0 { live = false; return }
                try? await Task.sleep(for: .seconds(left))
            }
        }
    }
}

/// The dots behind `HeroArtwork`, laid out once per size and redrawn per frame only while something moves.
/// Drawn in a few batches by brightness, so a frame is a handful of fills rather than thousands.
@MainActor final class HalftoneField {
    static var rippled = false
    static let pulseLife = 1.5
    private struct Dot { var x, y, r: CGFloat; var level: Int; var distance: CGFloat }
    private static let levels = 6
    private var size = CGSize.zero
    private var dots: [Dot] = []
    private var farthest: CGFloat = 1
    private var rippleStart: Double?
    private var pulses: [Double] = []
    private var last = 0.0
    private var follow = CGPoint(x: -1e4, y: -1e4)
    private var power: CGFloat = 0
    var awakeUntil = 0.0

    func ripple(at t: Double) { rippleStart = t }
    func pulse(at t: Double) { pulses.append(t); if pulses.count > 3 { pulses.removeFirst() } }

    private func layout(_ size: CGSize) {
        self.size = size; dots.removeAll(keepingCapacity: true)
        let step: CGFloat = 4
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        farthest = max(1, hypot(size.width / 2, size.height / 2))
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
                    let level = min(Self.levels - 1, Int(min(1, cloud) * Double(Self.levels)))
                    dots.append(Dot(x: x, y: y, r: r, level: level, distance: hypot(x - center.x, y - center.y) / farthest))
                }
                x += step
            }
            y += step
        }
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Double, pointer: CGPoint?, still: Bool) {
        if size != self.size { layout(size) }
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [Color(red: 0.03, green: 0.22, blue: 0.16), Color(red: 0.05, green: 0.40, blue: 0.27), Color(red: 0.10, green: 0.55, blue: 0.36)]),
            startPoint: .zero, endPoint: CGPoint(x: size.width * 0.4, y: size.height)))

        // The swell follows the pointer through an exponential spring, frame-rate independent, so it trails a little.
        let dt = min(0.05, max(0, now - last)); last = now
        if let p = pointer {
            if power < 0.01 { follow = p }
            let k = 1 - exp(-dt * 10)
            follow.x += (p.x - follow.x) * k; follow.y += (p.y - follow.y) * k
        }
        power += ((pointer == nil ? 0 : 1) - power) * (1 - exp(-dt * 6))
        pulses.removeAll { now - $0 > Self.pulseLife }

        let rippling = rippleStart.map { now - $0 < 2.2 } ?? false
        if !rippling { rippleStart = nil }
        let animate = !still && (rippling || power > 0.004 || !pulses.isEmpty)
        let sigma2: CGFloat = 70 * 70
        var batches = Array(repeating: Path(), count: Self.levels)
        for d in dots {
            var s: CGFloat = 1
            if animate {
                if let start = rippleStart {
                    // Each dot waits for the wave to leave the notch, then grows in over 0.7 s.
                    let t = min(1, max(0, (now - start - Double(d.distance) * 1.1) / 0.7))
                    if t <= 0 { continue }
                    s = 1 - pow(1 - t, 3)
                }
                if power > 0.004 {
                    let dx = d.x - follow.x, dy = d.y - follow.y
                    s *= 1 + 0.75 * power * exp(-(dx * dx + dy * dy) / sigma2)
                }
                for p in pulses {
                    let age = (now - p) / Self.pulseLife
                    let front = CGFloat(age) * 1.25
                    let gap = (d.distance - front) / 0.07
                    s *= 1 + 0.6 * CGFloat(1 - age) * exp(-gap * gap)
                }
            }
            let r = d.r * s
            if r < 0.3 { continue }
            batches[d.level].addEllipse(in: CGRect(x: d.x - r / 2, y: d.y - r / 2, width: r, height: r))
        }
        for (i, path) in batches.enumerated() where !path.isEmpty {
            ctx.fill(path, with: .color(.white.opacity(0.22 + 0.5 * (Double(i) + 0.5) / Double(Self.levels))))
        }
        let starsIn = rippleStart.map { min(1, max(0, (now - $0 - 0.9) / 0.6)) } ?? 1
        for (i, star) in [(0.12, 0.2), (0.31, 0.12), (0.58, 0.18), (0.82, 0.1), (0.9, 0.34), (0.44, 0.07), (0.7, 0.28)].enumerated() {
            let r: CGFloat = i % 3 == 0 ? 1.6 : 1
            ctx.fill(Path(ellipseIn: CGRect(x: star.0 * size.width, y: star.1 * size.height, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.7 * (still ? 1 : starsIn))))
        }
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
