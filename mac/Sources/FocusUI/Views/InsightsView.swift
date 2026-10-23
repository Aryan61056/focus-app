import SwiftUI

/// First native slice of Insights: how well Focus is reading you, from saved counts and your own Review answers.
/// The hours-by-day charts from the design board come later.
struct InsightsView: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    @State private var width: CGFloat = 900
    /// Side by side when there is room, stacked when the window is narrow.
    var wide: Bool { width >= 860 }

    var body: some View {
        let t = store.readTotals
        let a = store.agreement
        let streak = Rewards.streak(store.sessions, today: .now)
        Scroller {
            VStack(alignment: .leading, spacing: Space.xl) {
                if t.total == 0 {
                    EmptyState(symbol: "chart.bar", title: "Nothing to show yet", text: "Insights appear after your first session. Start one from Today.")
                } else {
                    // The banner says something the numbers under it do not: the streak, or how Focus reads your pattern.
                    PageBanner(key: "insights", symbol: "flame.fill", text: streak.current >= 1 ? "\(streak.current) focus \(streak.current == 1 ? "day" : "days") in a row" : "Your focus, by the hour",
                               detail: streak.current >= 1 ? nil : "from your sessions", phase: 1.3)
                    // A few numbers lead; the charts carry the rest.
                    Totals(items: headline(t, a))
                    if wide {
                        HStack(alignment: .top, spacing: Space.l) { heat; if c.prefs.showProgress { ProgressInsights(store: store).frame(width: 360) } }
                    } else {
                        VStack(alignment: .leading, spacing: Space.l) { heat; if c.prefs.showProgress { ProgressInsights(store: store) } }
                    }
                    reading(t, a)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, Space.xl)   // the page has no bottom padding of its own, so this scrolls to the window's edge
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }.scrollIndicators(.hidden)
    }

    func headline(_ t: ReadStats, _ a: (agreed: Int, answered: Int)) -> [(value: String, label: String)] {
        var out: [(value: String, label: String)] = [(durationText(store.sessions.reduce(0) { $0 + $1.activeSeconds }), "focused in all"), ("\(store.sessions.count)", "sessions")]
        if let morning = DayStats.morningSeconds(DayStats.heat(store.sessions)) { out.append((durationText(morning), "before noon")) }
        if a.answered > 0 { out.append(("\(a.agreed)/\(a.answered)", "calls you agreed with")) }
        return out
    }

    var heat: some View {
        Panel {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline) { Text("When you focus").font(Tokens.text(.callout, .semibold)); Spacer(); Text("by hour and day").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
                Heatmap(grid: DayStats.heat(store.sessions))
            }
        }
    }

    func reading(_ t: ReadStats, _ a: (agreed: Int, answered: Int)) -> some View {
        Panel {
            if wide {
                HStack(alignment: .top, spacing: Space.xxl) { readingSummary(t, a).frame(maxWidth: .infinity, alignment: .leading); readingFacts(t).frame(width: 320) }
            } else {
                VStack(alignment: .leading, spacing: Space.m) { readingSummary(t, a); readingFacts(t) }
            }
        }
    }

    func readingSummary(_ t: ReadStats, _ a: (agreed: Int, answered: Int)) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").foregroundStyle(Tokens.accent).accessibilityHidden(true)
                Text("How Hushd reads you").font(Tokens.text(.callout, .semibold))
            }.accessibilityAddTraits(.isHeader)
            ReadingSplit(stats: t)
            HStack(spacing: Space.l) { legend("On task", t.onTask); legend("Not sure", t.unsure); legend("Off topic", t.offTask) }
            Text(a.answered == 0 ? "Answer moments in Review to compare its calls with yours." : "From \(a.answered) Review answers, a small sample.")
                .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }

    func readingFacts(_ t: ReadStats) -> some View {
        VStack(spacing: 0) {
            fact("Readings", count: t.total)
            fact("Read by the model", count: t.model)
            fact("Settled by your rules", count: t.rule)
            if t.skipped > 0 { fact("Left alone (never-judged list)", "\(t.skipped)") }
            fact("Sessions", count: store.sessions.count)
        }
    }

    func legend(_ t: String, _ n: Int) -> some View { Text("\(n) \(t.lowercased())").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
    func fact(_ k: String, _ v: String) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Tokens.line)
            HStack { Text(k).foregroundStyle(Tokens.ink2); Spacer(); Text(v).monospacedDigit() }.font(Tokens.text(.body)).padding(.vertical, Space.xs)
        }
    }
    func fact(_ k: String, count: Int) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Tokens.line)
            HStack { Text(k).foregroundStyle(Tokens.ink2); Spacer(); CountText(value: count) }.font(Tokens.text(.body)).padding(.vertical, 8)
        }
    }
}

/// A whole number that counts up from zero the first time it appears, with digits that roll. Shows the number at once with Reduce Motion.
struct CountText: View {
    var value: Int
    @State private var shown = SnapshotMode.on
    @Environment(\.accessibilityReduceMotion) private var shownAtOnce
    var body: some View {
        let v = shown || shownAtOnce ? value : 0
        Text("\(v)").monospacedDigit().contentTransition(.numericText(value: Double(v)))
            .animation(.smooth(duration: 0.9), value: v)
            .onAppear { shown = true }
            .accessibilityLabel("\(value)")
    }
}

/// Hours 8 to 19 down, Monday to Sunday across, drawn as halftone: a bigger, brighter dot is more on-task time, the way the website prints
/// its art. The dots grow in as a diagonal wave from the top-left, and the one under the pointer swells and lights its row and day.
/// The figure is in each cell's accessibility label and help text.
struct Heatmap: View {
    var grid: [[Double]]
    @State private var hover: (day: Int, hour: Int)?
    @State private var shown = SnapshotMode.on
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let peak = max(grid.flatMap { $0 }.max() ?? 1, 1)
        let on = shown || reduceMotion
        // The hour column grows with the Text size setting, so "10:00" never breaks.
        let labelWidth = 36 * TextScale.shared.factor
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text("").frame(width: labelWidth)
                ForEach(0..<7, id: \.self) { d in
                    Text(Self.days[d]).font(Tokens.text(.caption2, hover?.day == d ? .semibold : .regular))
                        .foregroundStyle(hover?.day == d ? Tokens.ink : Tokens.ink2).frame(maxWidth: .infinity)
                }
            }
            ForEach(8..<20, id: \.self) { h in
                HStack(spacing: 2) {
                    Text("\(h):00").font(Tokens.rounded(.caption2, hover?.hour == h ? .bold : .semibold))
                        .foregroundStyle(hover?.hour == h ? Tokens.ink : Tokens.ink2).lineLimit(1).frame(width: labelWidth, alignment: .trailing)
                    ForEach(0..<7, id: \.self) { d in
                        let v = grid[d][h]
                        let f = v > 0 ? CGFloat(sqrt(v / peak)) : 0
                        let here = hover?.day == d && hover?.hour == h
                        let line = hover?.day == d || hover?.hour == h
                        Circle()
                            .fill(v > 0 ? Tokens.accent.opacity(0.35 + 0.65 * f) : Tokens.ink.opacity(line ? 0.22 : 0.12))
                            .frame(width: v > 0 ? 4 + 11 * f : 3, height: v > 0 ? 4 + 11 * f : 3)
                            .scaleEffect(on ? (here ? 1.3 : 1) : 0.001)
                            .animation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.25).delay(on && hover == nil ? Double(d + h - 8) * 0.03 : 0), value: on)
                            .animation(reduceMotion ? nil : Motion.notchSettle, value: here)
                            .frame(maxWidth: .infinity).frame(height: 19)
                            .contentShape(Rectangle())
                            .onHover { inside in if inside { hover = (d, h) } else if hover?.day == d && hover?.hour == h { hover = nil } }
                            .help(v > 0 ? "\(Self.days[d]) \(h):00: \(Int(v / 60)) minutes on task" : "\(Self.days[d]) \(h):00: nothing yet")
                            .accessibilityElement().accessibilityLabel("\(Self.days[d]) \(h):00, \(Int(v / 60)) minutes on task")
                    }
                }
            }
            // One line that answers the grid: the dot under the pointer, or the best hour when nothing is hovered. Beside it, what size means;
            // in a narrow page the key goes under the line instead of squeezing it.
            let line = Text(readout(peak))
                .font(Tokens.text(.caption, .medium)).foregroundStyle(Tokens.ink).lineLimit(1)
                .contentTransition(.interpolate).animation(reduceMotion ? nil : Motion.hover, value: readout(peak))
            let key = HStack(spacing: 5) {
                Text("Less").font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { f in
                    Circle().fill(Tokens.accent.opacity(f == 0 ? 0.3 : 0.35 + 0.65 * sqrt(f))).frame(width: 4 + 11 * sqrt(f), height: 4 + 11 * sqrt(f)).frame(width: 15, height: 15)
                }
                Text("More").font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2)
            }
            .fixedSize()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { line.fixedSize(); Spacer(minLength: 8); key }
                VStack(alignment: .leading, spacing: Space.xs) { line; key }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12).padding(.leading, labelWidth + 2)
            .accessibilityElement(children: .ignore).accessibilityLabel(readout(peak))
        }
        .onAppear { shown = true }
    }

    func readout(_ peak: Double) -> String {
        if let h = hover {
            let v = grid[h.day][h.hour]
            return v > 0 ? "\(Self.days[h.day]) \(h.hour):00 · \(Int(v / 60)) min on task" : "\(Self.days[h.day]) \(h.hour):00 · nothing yet"
        }
        var best: (Int, Int, Double)?
        for d in 0..<7 { for hr in 8..<20 where grid[d][hr] > (best?.2 ?? 0) { best = (d, hr, grid[d][hr]) } }
        guard let b = best else { return "Hover a dot to see the minutes" }
        return "Best hour: \(Self.days[b.0]) \(b.1):00 · \(Int(b.2 / 60)) min on task"
    }
}

/// How you recover, not how often you slip: time to get back on task, the longest stretch, the best run of focus days.
/// Each figure appears only when there is enough behind it, and nothing here is ranked or scored.
struct ProgressInsights: View {
    @Bindable var store: DataStore
    var body: some View {
        let trend = Rewards.returnTrend(store.sessions, today: .now)
        let streak = Rewards.streak(store.sessions, today: .now)
        let best = Rewards.bestStretch(store.sessions)
        let cues = Rewards.cueResponses(store.sessions, today: .now)
        let timing = Rewards.slipTiming(store.sessions, today: .now)
        if trend != nil || best >= Rewards.notableStretch || streak.best >= 2 || cues.count >= 2 || timing != nil {
            Panel {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Getting back on track").font(Tokens.text(.callout, .semibold)).accessibilityAddTraits(.isHeader)
                    if let t = trend {
                        Text(headline(t)).font(Tokens.rounded(.title3, .semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 0) {
                        if let t = trend {
                            fact("Average return this week", Rewards.duration(t.thisWeek.average))
                            if let l = t.lastWeek { fact("Average return last week", Rewards.duration(l.average)) }
                        }
                        if best >= Rewards.notableStretch { fact("Longest stretch without a slip", Rewards.duration(best)) }
                        if streak.best >= 2 { fact("Most focus days in a row", "\(streak.best)") }
                    }
                    if let timing { SlipTimingBars(timing: timing) }
                    if cues.count >= 2 { CueResponseRows(cues: cues) }
                    if trend != nil {
                        Text("A return is the time from drifting to being back on task. Practice sessions and weeks with fewer than three returns are left out.")
                            .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    func headline(_ t: (thisWeek: Rewards.Returns, lastWeek: Rewards.Returns?)) -> String {
        guard let l = t.lastWeek else { return "You are getting back on task in about \(Rewards.duration(t.thisWeek.average))." }
        if t.thisWeek.average <= 0.85 * l.average { return "You got back faster this week: about \(Rewards.duration(t.thisWeek.average)), down from \(Rewards.duration(l.average))." }
        return "You are getting back on task in about \(Rewards.duration(t.thisWeek.average))."
    }
    func fact(_ k: String, _ v: String) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Tokens.line)
            HStack { Text(k).foregroundStyle(Tokens.ink2); Spacer(); Text(v).monospacedDigit() }.font(Tokens.text(.body)).padding(.vertical, Space.xs)
        }
    }
}

/// What brings you back: the typical time from each cue appearing to being back on task, as small bars. It shows what was on screen when
/// you came back, not what caused it, and says so. Only cues with at least three returns appear, and only when two or more can be compared.
struct CueResponseRows: View {
    var cues: [Rewards.CueResponse]
    var body: some View {
        let slowest = max(cues.map(\.median).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Text("What brings you back").font(Tokens.text(.body, .semibold))
                InfoTip(text: "The typical time from each cue appearing to you being back on task, over the last 30 days. It shows what was on screen when you came back, not proof that it was the reason. Hushd does not change anything because of it.")
            }
            ForEach(Array(cues.enumerated()), id: \.offset) { _, r in
                HStack(spacing: Space.s) {
                    Text(r.cue?.label ?? "Before any cue").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).frame(width: 118, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(Tokens.accent.opacity(0.55)).frame(width: max(6, g.size.width * r.median / slowest))
                    }.frame(height: 6)
                    Text(Rewards.duration(r.median)).font(Tokens.text(.caption)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.cue?.label ?? "Before any cue"): about \(Rewards.duration(r.median)), \(r.count) times")
            }
        }
    }
}

/// When slips start, in ten-minute steps of a session, as six small bars. A peak is named only when it holds a clear share.
struct SlipTimingBars: View {
    var timing: Rewards.SlipTiming
    var body: some View {
        let top = max(timing.buckets.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Text("When slips start").font(Tokens.text(.body, .semibold))
                InfoTip(text: "Minutes into a session when you first drifted, over the last 30 days. Only the minute is kept, never what you drifted into.")
            }
            HStack(alignment: .bottom, spacing: Space.xs) {
                ForEach(0..<6, id: \.self) { i in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: Tokens.radiusTiny, style: .continuous)
                            .fill(timing.peak == i ? Tokens.accent : Tokens.accent.opacity(0.35))
                            .frame(height: max(4, 44 * CGFloat(timing.buckets[i]) / CGFloat(top)))
                        Text(Rewards.SlipTiming.label(i)).font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Rewards.SlipTiming.label(i)) minutes in: \(timing.buckets[i]) slips")
                }
            }
            .frame(height: 64, alignment: .bottom)
            if let p = timing.peak {
                Text("Most slips start \(Rewards.SlipTiming.label(p)) minutes in.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
            }
        }
    }
}
