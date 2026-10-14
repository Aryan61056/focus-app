import SwiftUI

/// Today's sessions laid along the clock. On task is a solid bar, not sure is hatched, off topic is a thin low bar.
struct DayTrack: View {
    var slices: [DaySlice]
    var range: ClosedRange<Int>
    var nowHour: Double?
    var body: some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in
                let span = Double(range.upperBound - range.lowerBound)
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10), with: .color(Tokens.control))
                for s in slices {
                    let x = (s.startHour - Double(range.lowerBound)) / span * size.width
                    let w = max(2, s.hours / span * size.width)
                    switch s.kind {
                    case .on: ctx.fill(Path(roundedRect: CGRect(x: x, y: 6, width: w, height: size.height - 12), cornerRadius: 4), with: .color(Tokens.accent))
                    case .unsure:
                        var dashes = Path(); var dx = x
                        while dx < x + w { dashes.addRect(CGRect(x: dx, y: 6, width: min(3, x + w - dx), height: size.height - 12)); dx += 6 }
                        ctx.fill(dashes, with: .color(Tokens.ink2))
                    case .off: ctx.fill(Path(roundedRect: CGRect(x: x, y: size.height / 2 - 6, width: w, height: 12), cornerRadius: 2), with: .color(Tokens.ink.opacity(0.28)))
                    case .gap: break
                    }
                }
                if let n = nowHour, range.contains(Int(n)) { ctx.fill(Path(CGRect(x: (n - Double(range.lowerBound)) / span * size.width - 1, y: 0, width: 2, height: size.height)), with: .color(Tokens.ink)) }
            }
            .frame(height: 34)
            GeometryReader { g in
                let span = CGFloat(range.upperBound - range.lowerBound)
                ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: 2)), id: \.self) { h in
                    Text("\(h)").font(Tokens.rounded(11.5)).foregroundStyle(Tokens.ink2).position(x: min(max(CGFloat(h - range.lowerBound) / span * g.size.width, 8), g.size.width - 8), y: 8)
                }
            }.frame(height: 16).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Focus timeline for today")
    }
}

struct WeekBars: View {
    var days: [(day: Date, hours: Double)]
    var body: some View {
        let top = max(2, (days.map(\.hours).max() ?? 0).rounded(.up))
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6).fill(Tokens.control).frame(height: 72)
                        RoundedRectangle(cornerRadius: 6).fill(Tokens.accent.opacity(i == days.count - 1 ? 1 : 0.55)).frame(height: max(d.hours > 0 ? 4 : 0, 72 * d.hours / top))
                    }
                    Text(d.day.formatted(.dateTime.weekday(.abbreviated))).font(Tokens.text(11.5, i == days.count - 1 ? .semibold : .regular)).foregroundStyle(i == days.count - 1 ? Tokens.ink : Tokens.ink2)
                }.frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(d.day.formatted(.dateTime.weekday(.wide))): \(durationText(d.hours * 3600)) on task")
            }
        }
    }
}
