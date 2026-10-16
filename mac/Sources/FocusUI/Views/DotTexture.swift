import SwiftUI

/// A regular grid of small dots, drawn once. `Equatable` and wrapped in `.equatable()` by every caller, so SwiftUI never redraws it
/// while a mask, a scale or a position around it moves. Used as the printed texture inside chart bars.
struct DotGrid: View, Equatable {
    var color: Color = Tokens.ink
    var step: CGFloat = 7
    var radius: CGFloat = 0.7
    var opacity: Double = 0.1

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += step
                }
                y += step
            }
            ctx.fill(path, with: .color(color.opacity(opacity)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Wipes the view in from the leading edge once, as a chart draws itself. Replays when the screen is opened again.
    func sweepIn(delay: Double = 0, duration: Double = 0.7) -> some View { modifier(SweepIn(delay: delay, duration: duration)) }
}

private struct SweepIn: ViewModifier {
    var delay: Double
    var duration: Double
    @State private var shown = SnapshotMode.on
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask {
                GeometryReader { g in
                    Rectangle().frame(width: shown || reduceMotion ? g.size.width + 8 : 0, height: g.size.height + 8)
                        .animation(Motion.out(duration).delay(delay), value: shown)
                        .frame(width: g.size.width, height: g.size.height, alignment: .leading)
                }
            }
            .onAppear { shown = true }
    }
}

/// Springs a bar or dot up from its base the first time it appears. `index` staggers neighbours 40 ms apart.
struct GrowIn: ViewModifier {
    var index = 0
    var anchor: UnitPoint = .bottom
    var axis: Axis = .vertical
    @State private var shown = SnapshotMode.on
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let on = shown || reduceMotion
        content
            .scaleEffect(x: axis == .horizontal && !on ? 0.001 : 1, y: axis == .vertical && !on ? 0.001 : 1, anchor: anchor)
            .opacity(on ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.18).delay(Double(index) * 0.04), value: shown)
            .onAppear { shown = true }
    }
}
