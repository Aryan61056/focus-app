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
            .sweepIn(duration: 0.8)
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

/// Seven days as slim columns on a baseline, today in full accent and the rest softer, with the hours above each so no axis is needed.
struct WeekBars: View {
    var days: [(day: Date, hours: Double)]
    var body: some View {
        let top = max(2, (days.map(\.hours).max() ?? 0).rounded(.up))
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    let today = i == days.count - 1
                    VStack(spacing: 6) {
                        Text(d.hours > 0 ? Self.short(d.hours) : "").font(Tokens.rounded(11.5, today ? .semibold : .medium))
                            .foregroundStyle(today ? Tokens.ink : Tokens.ink2).monospacedDigit()
                        UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6, style: .continuous)
                            .fill(Tokens.accent.opacity(today ? 1 : 0.5))
                            // Printed with the same micro dots as the cards, so a bar reads as halftone rather than a flat block.
                            .overlay { DotGrid(color: Tokens.onAccent, step: 4, radius: 0.7, opacity: today ? 0.3 : 0.45).equatable().clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6, style: .continuous)) }
                            .frame(maxWidth: 34).frame(height: max(d.hours > 0 ? 4 : 0, 76 * d.hours / top))
                            .modifier(GrowIn(index: i))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(d.day.formatted(.dateTime.weekday(.wide))): \(durationText(d.hours * 3600)) on task")
                }
            }
            .frame(height: 100)
            Rectangle().fill(Tokens.track).frame(height: 1)
            HStack(spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    let today = i == days.count - 1
                    Text(d.day.formatted(.dateTime.weekday(.abbreviated))).font(Tokens.text(11.5, today ? .semibold : .regular))
                        .foregroundStyle(today ? Tokens.ink : Tokens.ink2).frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6).accessibilityHidden(true)
        }
    }
    static func short(_ h: Double) -> String { h < 1 ? "\(Int((h * 60).rounded()))m" : String(format: "%.1fh", h) }
}
