import SwiftUI

/// What a halftone field shows: a value from 0 to 1 at each point (u and v run 0 to 1 across the field), the dot color, and how big and
/// bright the dots get. The same idea as the Mac app's `Halftone` and the website's art, drawn here so nothing ships as an image.
struct HalftonePattern {
    var step: CGFloat = 4
    var maxDot: CGFloat = 3.2
    var color: Color = .white
    var opacity: ClosedRange<Double> = 0.22...0.72
    /// Where ripples and waves start, in unit coordinates of the field.
    var origin: UnitPoint = .center
    /// Seconds for the arrival ripple to cross the field.
    var rippleSpan = 1.1
    var background: Gradient?
    var stars = false
    var value: (CGFloat, CGFloat) -> CGFloat
}

extension HalftonePattern {
    private static let night = Gradient(colors: [Color(red: 0.03, green: 0.22, blue: 0.16), Color(red: 0.05, green: 0.40, blue: 0.27), Color(red: 0.10, green: 0.55, blue: 0.36)])

    /// Two printed hills under a night sky: the Mac's Today banner.
    static let hills = HalftonePattern(background: night, stars: true) { u, v in
        let hill1 = v - (0.72 - 0.18 * sin(u * 5.2 + 0.6) - 0.06 * sin(u * 13))
        let hill2 = v - (0.38 + 0.22 * cos(u * 3.4 + 1.9) + 0.05 * sin(u * 17 + 2))
        let crest1 = max(0, 1 - abs(hill1) * 4.5), crest2 = max(0, 1 - abs(hill2) * 5)
        return crest1 * crest1 * 1.1 + crest2 * crest2 * 0.9 + (hill1 > 0 ? 0.3 + 0.25 * sin(u * 40 + v * 23) * sin(u * 11) : 0)
    }

    /// The hills with the ridges moved along, so each page's banner is clearly the same art but not a copy.
    static func ridge(phase: Double) -> HalftonePattern {
        HalftonePattern(background: night, stars: true) { u, v in
            let a = CGFloat(phase)
            let hill1 = v - (0.70 - 0.2 * sin(u * 4.4 + a) - 0.05 * sin(u * 11 + a))
            let hill2 = v - (0.34 + 0.2 * cos(u * 3.0 + a * 1.7) + 0.04 * sin(u * 15 + a))
            let crest1 = max(0, 1 - abs(hill1) * 5), crest2 = max(0, 1 - abs(hill2) * 5.5)
            return crest1 * crest1 * 1.1 + crest2 * crest2 * 0.9 + (hill1 > 0 ? 0.28 + 0.22 * sin(u * 38 + v * 21) * sin(u * 9 + a) : 0)
        }
    }

    /// Concentric printed rings around a symbol: behind the session ring, so a change of state sends a wave out through them.
    /// `hole` keeps the middle clear (as a fraction of the field), so nothing prints behind the clock.
    static func rings(color: Color = Palette.accent, center: UnitPoint = .center, aspect: CGFloat = 1, hole: CGFloat = 0) -> HalftonePattern {
        HalftonePattern(step: 6, maxDot: 3.4, color: color, opacity: 0.16...0.6, origin: center, rippleSpan: 0.9) { u, v in
            let d = hypot((u - center.x) * aspect, v - center.y)
            if d < hole { return 0 }
            let e = d - hole
            return pow(max(0, 1 - e * 3.4), 1.3) * (0.5 + 0.5 * cos(e * 34))
        }
    }

    /// A soft bloom from one corner, for a moment worth marking (a phone that just paired).
    static func bloom(from corner: UnitPoint, aspect: CGFloat) -> HalftonePattern {
        HalftonePattern(step: 5, maxDot: 3, color: Palette.accent, opacity: 0.2...0.75, origin: corner, rippleSpan: 0.8) { u, v in
            let d = hypot((u - corner.x) * aspect, v - corner.y)
            return pow(max(0, 1 - d * 0.55), 1.7) * (0.7 + 0.3 * sin(u * 23 + v * 9))
        }
    }
}

/// A halftone field that moves like the website's art: the dots ripple out from the origin when it arrives (once per launch for a
/// given key), swell under a finger and trail it as if they had weight, and a wave runs out from the origin each time `pulse`
/// changes. Nothing redraws while nothing moves, so it costs nothing at rest. Reduce Motion draws it still.
struct Halftone: View {
    enum Ripple { case never, onAppear, oncePerLaunch(String) }
    var pattern: HalftonePattern
    var ripple: Ripple = .onAppear
    var pulse = 0
    var followsTouch = true
    @State private var field = HalftoneField()
    @State private var live = false
    @State private var touch: CGPoint?
    @State private var sleep: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !live || reduceMotion)) { timeline in
            Canvas { ctx, size in
                field.draw(&ctx, size: size, pattern: pattern, now: timeline.date.timeIntervalSinceReferenceDate, pointer: touch, still: reduceMotion)
            }
        }
        // A finger on the art swells the dots under it. Simultaneous, so a scroll that starts here still scrolls.
        .simultaneousGesture(followsTouch && !reduceMotion ? DragGesture(minimumDistance: 0)
            .onChanged { touch = $0.location; wake(for: 1.2) }
            .onEnded { _ in touch = nil; wake(for: 1.2) } : nil)
        .onAppear {
            guard !reduceMotion else { return }
            switch ripple {
            case .never: return
            case .onAppear: break
            case .oncePerLaunch(let key): if HalftoneField.rippled.contains(key) { return } else { HalftoneField.rippled.insert(key) }
            }
            field.ripple(at: Date.now.timeIntervalSinceReferenceDate); wake(for: pattern.rippleSpan + 1.3)
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

/// The dots behind `Halftone`, laid out once per size and redrawn per frame only while something moves. Drawn in a few batches by
/// brightness, so a frame is a handful of fills rather than thousands.
@MainActor final class HalftoneField {
    static var rippled: Set<String> = []
    static let pulseLife = 1.5
    private struct Dot { var x, y, r: CGFloat; var level: Int; var distance: CGFloat }
    private static let levels = 6
    private var size = CGSize.zero
    private var dots: [Dot] = []
    private var rippleStart: Double?
    private var pulses: [Double] = []
    private var last = 0.0
    private var follow = CGPoint(x: -1e4, y: -1e4)
    private var power: CGFloat = 0
    var awakeUntil = 0.0

    func ripple(at t: Double) { rippleStart = t }
    func pulse(at t: Double) { pulses.append(t); if pulses.count > 3 { pulses.removeFirst() } }

    private func layout(_ size: CGSize, _ p: HalftonePattern) {
        self.size = size; dots.removeAll(keepingCapacity: true)
        let o = CGPoint(x: p.origin.x * size.width, y: p.origin.y * size.height)
        let farthest = max(1, hypot(max(o.x, size.width - o.x), max(o.y, size.height - o.y)))
        var y = p.step / 2
        while y < size.height {
            var x = p.step / 2
            while x < size.width {
                let cloud = p.value(x / size.width, y / size.height)
                let r = min(p.maxDot, cloud * p.maxDot * 0.94)
                if r > p.maxDot * 0.11 {
                    let level = min(Self.levels - 1, Int(min(1, cloud) * Double(Self.levels)))
                    dots.append(Dot(x: x, y: y, r: r, level: level, distance: hypot(x - o.x, y - o.y) / farthest))
                }
                x += p.step
            }
            y += p.step
        }
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, pattern p: HalftonePattern, now: Double, pointer: CGPoint?, still: Bool) {
        if size != self.size { layout(size, p) }
        if let g = p.background {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(g, startPoint: .zero, endPoint: CGPoint(x: size.width * 0.4, y: size.height)))
        }
        // The swell follows the finger through an exponential spring, frame-rate independent, so it trails a little.
        let dt = min(0.05, max(0, now - last)); last = now
        if let ptr = pointer {
            if power < 0.01 { follow = ptr }
            let k = 1 - exp(-dt * 10)
            follow.x += (ptr.x - follow.x) * k; follow.y += (ptr.y - follow.y) * k
        }
        power += ((pointer == nil ? 0 : 1) - power) * (1 - exp(-dt * 6))
        pulses.removeAll { now - $0 > Self.pulseLife }

        let rippling = rippleStart.map { now - $0 < p.rippleSpan + 1.1 } ?? false
        if !rippling { rippleStart = nil }
        let animate = !still && (rippling || power > 0.004 || !pulses.isEmpty)
        let sigma2: CGFloat = 60 * 60
        var batches = Array(repeating: Path(), count: Self.levels)
        for d in dots {
            var s: CGFloat = 1
            if animate {
                if let start = rippleStart {
                    // Each dot waits for the wave to leave the origin, then grows in over 0.7 s.
                    let t = min(1, max(0, (now - start - Double(d.distance) * p.rippleSpan) / 0.7))
                    if t <= 0 { continue }
                    s = 1 - pow(1 - t, 3)
                }
                if power > 0.004 {
                    let dx = d.x - follow.x, dy = d.y - follow.y
                    s *= 1 + 0.75 * power * exp(-(dx * dx + dy * dy) / sigma2)
                }
                for pulse in pulses {
                    let age = (now - pulse) / Self.pulseLife
                    let gap = (d.distance - CGFloat(age) * 1.25) / 0.07
                    s *= 1 + 0.6 * CGFloat(1 - age) * exp(-gap * gap)
                }
            }
            let r = d.r * s
            if r < 0.3 { continue }
            batches[d.level].addEllipse(in: CGRect(x: d.x - r / 2, y: d.y - r / 2, width: r, height: r))
        }
        let lo = p.opacity.lowerBound, span = p.opacity.upperBound - lo
        for (i, path) in batches.enumerated() where !path.isEmpty {
            ctx.fill(path, with: .color(p.color.opacity(lo + span * (Double(i) + 0.5) / Double(Self.levels))))
        }
        if p.stars {
            let starsIn = rippleStart.map { min(1, max(0, (now - $0 - 0.9) / 0.6)) } ?? 1
            for (i, star) in [(0.12, 0.2), (0.31, 0.12), (0.58, 0.18), (0.82, 0.1), (0.9, 0.34), (0.44, 0.07), (0.7, 0.28)].enumerated() {
                let r: CGFloat = i % 3 == 0 ? 1.6 : 1
                ctx.fill(Path(ellipseIn: CGRect(x: star.0 * size.width, y: star.1 * size.height, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.7 * (still ? 1 : starsIn))))
            }
        }
    }
}
