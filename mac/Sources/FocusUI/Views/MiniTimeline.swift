import SwiftUI

/// A session as shapes, readable in grayscale: filled = on task, hatched = unsure, thin line = off topic, gap = paused.
struct MiniTimeline: View {
    var segments: [TimelineSegment]
    var height: CGFloat = 10
    var body: some View {
        Canvas { ctx, size in
            let total = segments.reduce(0) { $0 + $1.seconds }
            guard total > 0 else { return }
            let gap: CGFloat = 2
            var x: CGFloat = 0
            for s in segments {
                let w = max(2, (size.width - gap * CGFloat(segments.count - 1)) * s.seconds / total)
                let r = CGRect(x: x, y: 0, width: w, height: size.height)
                switch s.kind {
                case .on: ctx.fill(Path(roundedRect: r, cornerRadius: size.height / 2.4), with: .color(Tokens.accent))
                case .unsure:
                    var hatch = Path(); var hx = r.minX
                    while hx < r.maxX { hatch.addRect(CGRect(x: hx, y: r.minY, width: min(2, r.maxX - hx), height: r.height)); hx += 4 }
                    ctx.fill(hatch, with: .color(Tokens.ink2))
                case .off: ctx.fill(Path(CGRect(x: r.minX, y: r.midY - 1, width: r.width, height: 2)), with: .color(Tokens.ink2.opacity(0.6)))
                case .gap: break
                }
                x += w + gap
            }
        }
        .frame(height: height)
        .accessibilityLabel(Self.describe(segments))
    }

    static func describe(_ s: [TimelineSegment]) -> String {
        func m(_ k: TimelineSegment.Kind) -> Int { Int((s.filter { $0.kind == k }.reduce(0) { $0 + $1.seconds } / 60).rounded()) }
        return "\(m(.on)) minutes on task, \(m(.unsure)) unsure, \(m(.off)) off topic"
    }
}

func durationText(_ seconds: Double) -> String {
    let m = Int((seconds / 60).rounded())
    return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60)) min" : "\(m) min"
}

func sessionSentence(_ r: SessionRecord) -> String {
    let on = Int((r.onTaskSeconds / 60).rounded())
    let slips = r.drifts == 0 ? "No slips." : (r.drifts == 1 ? "One slip." : "\(r.drifts) slips.")
    return "\(on) minute\(on == 1 ? "" : "s") on task. \(slips)"
}
