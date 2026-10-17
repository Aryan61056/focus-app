import SwiftUI
import AppKit

/// The ring carries state by shape first, color second: closed = on task, dashed = unsure, gapped = drifting,
/// bars = paused, dot = break, arc = timed progress (docs/design, PRODUCT.md accessibility baseline).
public enum RingState: Equatable, Sendable {
    case on, unsure, drift, paused, breakTime
    /// A closed ring with a tick: a quick return or a goal reached. Shape, not color, carries it.
    case done
    case progress(Double)

    /// The ring's shape, ignoring how far a progress arc has run. A new shape is worth a transition; a second of progress is not.
    public var shape: Int {
        switch self { case .on: return 0; case .unsure: return 1; case .drift: return 2; case .paused: return 3; case .breakTime: return 4; case .done: return 5; case .progress: return 6 }
    }
    var fraction: Double { if case .progress(let f) = self { return min(max(f, 0), 1) }; return 0 }
}

public struct RingView: View {
    public var state: RingState
    public var color: Color
    public init(_ state: RingState, color: Color = Tokens.ink) { self.state = state; self.color = color }

    public var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = s * 6 / 18, lw = s * 2.25 / 18
            let style = StrokeStyle(lineWidth: lw, lineCap: .round)
            func arc(from deg: Double, sweep: Double) -> Path {
                Path { p in p.addArc(center: c, radius: r, startAngle: .degrees(deg), endAngle: .degrees(deg + sweep), clockwise: false) }
            }
            let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            switch state {
            case .on:
                ctx.stroke(circle, with: .color(color), style: style)
            case .unsure:
                let circ = 2 * Double.pi * Double(r)
                ctx.stroke(circle, with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .round, dash: [circ * 2.4 / 37.7 - lw * 0.0, circ * 2.4 / 37.7]))
            case .drift:
                ctx.stroke(arc(from: -60, sweep: 281.5), with: .color(color), style: style)
            case .paused:
                let w = s * 2.8 / 18, h = s * 10 / 18
                for x in [5.2, 10.0] {
                    ctx.fill(Path(roundedRect: CGRect(x: s * x / 18 + (size.width - s) / 2, y: s * 4 / 18 + (size.height - s) / 2, width: w, height: h), cornerRadius: w / 2), with: .color(color))
                }
            case .breakTime:
                ctx.stroke(circle, with: .color(color), style: style)
                let d = s * 1.9 / 18 * 2
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)), with: .color(color))
            case .done:
                ctx.stroke(circle, with: .color(color), style: style)
                let tick = Path { p in
                    p.move(to: CGPoint(x: c.x - r * 0.42, y: c.y + r * 0.02))
                    p.addLine(to: CGPoint(x: c.x - r * 0.1, y: c.y + r * 0.36))
                    p.addLine(to: CGPoint(x: c.x + r * 0.46, y: c.y - r * 0.32))
                }
                ctx.stroke(tick, with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            case .progress:
                ctx.stroke(circle, with: .color(Tokens.track), style: style)
            }
        }
        // The arc is a shape on top, not part of the Canvas, so it can sweep between ticks instead of jumping.
        .overlay { if case .progress = state { arc } }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)  // the surrounding label says the state in words
    }

    private var arc: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ProgressArc(fraction: state.fraction).stroke(color, style: StrokeStyle(lineWidth: s * 2.25 / 18, lineCap: .round))
        }
    }
}

/// The timed arc: same radius as the Canvas ring (6/18 of the side), from twelve o'clock, clockwise. Animatable, so it sweeps.
struct ProgressArc: Shape {
    var fraction: Double
    var animatableData: Double { get { fraction } set { fraction = newValue } }
    func path(in rect: CGRect) -> Path {
        guard fraction > 0 else { return Path() }
        let s = min(rect.width, rect.height), r = s * 6 / 18
        return Path { p in p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false) }
    }
}

/// RingView that moves: a new shape blurs in over the old one, like an SF Symbol replace. Reduce Motion keeps a short cross-fade.
/// A timed arc steps once a second and is not animated: a one-second sweep started every second never ends, so every ring on screen
/// (toolbar, sidebar, notch, Today) redrew at the display's rate for the whole session, about 40 percent of a core. A 25 minute arc
/// moves a quarter of a degree a second, which no one can see sweep.
public struct LiveRing: View {
    var state: RingState
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(_ state: RingState, color: Color = Tokens.ink) { self.state = state; self.color = color }

    public var body: some View {
        ZStack {
            RingView(state, color: color)
                .id(state.shape)
                .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .scale(scale: 0.8)))
        }
        // A change of state gives the ring a small pop, so the eye catches it out of the corner.
        .keyframeAnimator(initialValue: 1.0, trigger: state.shape) { content, scale in
            content.scaleEffect(reduceMotion ? 1 : scale)
        } keyframes: { _ in
            SpringKeyframe(1.14, duration: 0.16, spring: .init(duration: 0.16, bounce: 0))
            SpringKeyframe(1, duration: 0.5, spring: .init(duration: 0.5, bounce: 0.35))
        }
        .animation(reduceMotion ? Motion.reduced : Motion.notchSettle, value: state.shape)
        .animation(Motion.out(0.3), value: color)
    }
}
