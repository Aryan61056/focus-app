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
                        RoundedRectangle(cornerRadius: 6).fill(Tokens.control).frame(height: 88)
                        RoundedRectangle(cornerRadius: 6).fill(Tokens.accent.opacity(i == days.count - 1 ? 1 : 0.55)).frame(height: max(d.hours > 0 ? 4 : 0, 88 * d.hours / top))
                    }
                    Text(d.day.formatted(.dateTime.weekday(.abbreviated))).font(Tokens.text(11.5, i == days.count - 1 ? .semibold : .regular)).foregroundStyle(i == days.count - 1 ? Tokens.ink : Tokens.ink2)
                }.frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(d.day.formatted(.dateTime.weekday(.wide))): \(durationText(d.hours * 3600)) on task")
            }
        }
    }
}

/// Today below the session: your day on a clock, the projects you can pick up, and the week.
struct TodayExtras: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    var body: some View {
        let today = Date.now
        let slices = DayStats.slices(store.sessions, on: today)
        let total = DayStats.total(store.sessions, on: today)
        VStack(alignment: .leading, spacing: 24) {
            if total.sessions > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) { SectionTitle(text: "Your day"); Spacer(); Text("hours of the day").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
                    DayTrack(slices: slices, range: DayStats.axis(for: slices), nowHour: DayStats.hourOfDay(today, .current))
                    Text("\(durationText(total.onTaskSeconds)) on task across \(total.sessions) session\(total.sessions == 1 ? "" : "s"). \(total.slips == 0 ? "No slips." : (total.slips == 1 ? "One slip." : "\(total.slips) slips."))")
                        .font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2)
                }
            }
            if !store.projects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: "Projects")
                    VStack(spacing: 0) {
                        ForEach(Array(store.projects.prefix(4))) { p in
                            let sessions = store.sessions(for: p.id)
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).font(Tokens.text(13.5, .semibold)).lineLimit(1)
                                    if !p.nextStep.isEmpty { Text("Next: \(p.nextStep)").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).lineLimit(1) }
                                }
                                Spacer()
                                Text(sessions.first.map { $0.start.formatted(.relative(presentation: .named)) } ?? "No sessions yet").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
                                Text(durationText(sessions.reduce(0) { $0 + $1.onTaskSeconds })).font(Tokens.text(12.5)).monospacedDigit().frame(width: 76, alignment: .trailing)
                                Button("Continue") { c.begin(task: p.name, projectId: p.id, autoTick: true) }.buttonStyle(FocusButtonStyle(.secondary, small: true)).disabled(c.isActive)
                            }
                            .padding(.vertical, 10)
                            Divider().overlay(Tokens.line)
                        }
                    }
                }
            }
            let week = DayStats.week(store.sessions, endingOn: today)
            if week.contains(where: { $0.hours > 0 }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) { SectionTitle(text: "This week"); Spacer(); Text("hours on task").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
                    WeekBars(days: week).frame(maxWidth: 520)
                    let best = week.max { $0.hours < $1.hours }!
                    Text("\(durationText(week.reduce(0) { $0 + $1.hours } * 3600)) on task. \(best.day.formatted(.dateTime.weekday(.wide))) was your longest day.").font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2)
                }
            }
        }
    }
}
