import SwiftUI
import AppKit

/// The ring carries state by shape first, color second: closed = on task, dashed = unsure, gapped = drifting,
/// bars = paused, dot = break, arc = timed progress (docs/design, PRODUCT.md accessibility baseline).
public enum RingState: Equatable, Sendable {
    case on, unsure, drift, paused, breakTime
    /// A closed ring with a tick: a quick return or a goal reached. Shape, not color, carries it.
    case done
    case progress(Double)
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
            case .progress(let f):
                ctx.stroke(circle, with: .color(Tokens.track), style: style)
                if f > 0 { ctx.stroke(arc(from: -90, sweep: 360 * min(max(f, 0), 1)), with: .color(color), style: style) }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)  // the surrounding label says the state in words
    }
}
