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
        Scroller {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Insights", subtitle: "Worked out on this Mac from your own sessions.")
                if t.total == 0 {
                    EmptyState(symbol: "chart.bar", title: "Nothing to show yet", text: "After a session, this shows when you focus best, how quickly you get back on task, and how often you agreed with Focus.")
                } else {
                    PageBanner(key: "insights", symbol: "chart.bar.fill", text: durationText(store.sessions.reduce(0) { $0 + $1.onTaskSeconds }) + " on task",
                               detail: "across \(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s")", phase: 1.4)
                    if let share = DayStats.morningShare(DayStats.heat(store.sessions)) {
                        Text("Mornings are your strongest time: \(share)% of your focused minutes fall before noon.")
                            .font(Tokens.rounded(20, .semibold)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 640, alignment: .leading)
                    }
                    if wide {
                        HStack(alignment: .top, spacing: 18) { heat; if c.prefs.showProgress { ProgressInsights(store: store).frame(width: 360) } }
                    } else {
                        VStack(alignment: .leading, spacing: 18) { heat; if c.prefs.showProgress { ProgressInsights(store: store) } }
                    }
                    reading(t, a)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }.scrollIndicators(.hidden)
    }

    var heat: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Text("When you focus").font(Tokens.text(15, .semibold)).accessibilityAddTraits(.isHeader)
                Heatmap(grid: DayStats.heat(store.sessions))
            }
        }
    }

    func reading(_ t: ReadStats, _ a: (agreed: Int, answered: Int)) -> some View {
        Panel {
            if wide {
                HStack(alignment: .top, spacing: 36) { readingSummary(t, a).frame(maxWidth: .infinity, alignment: .leading); readingFacts(t).frame(width: 320) }
            } else {
                VStack(alignment: .leading, spacing: 14) { readingSummary(t, a); readingFacts(t) }
            }
        }
    }

    func readingSummary(_ t: ReadStats, _ a: (agreed: Int, answered: Int)) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How well Focus is reading you").font(Tokens.text(15, .semibold)).accessibilityAddTraits(.isHeader)
            Text(a.answered == 0 ? "You have not answered any Review moments yet, so there is nothing to compare with." : "You agreed with \(a.agreed) of \(a.answered) calls.")
                .font(Tokens.rounded(19, .semibold)).fixedSize(horizontal: false, vertical: true)
            ReadingSplit(stats: t)
            HStack(spacing: 18) { legend("On task", t.onTask); legend("Not sure", t.unsure); legend("Off topic", t.offTask) }
            Text(a.answered == 0 ? "Answers in Review show whether Focus's calls match yours." : "The agreement figure counts only the \(a.answered) answers you gave in Review. That is a small sample, so read it loosely.")
                .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
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

    func legend(_ t: String, _ n: Int) -> some View { Text("\(t) \(n)").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
    func fact(_ k: String, _ v: String) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Tokens.line)
            HStack { Text(k).foregroundStyle(Tokens.ink2); Spacer(); Text(v).monospacedDigit() }.font(Tokens.text(13)).padding(.vertical, 8)
        }
    }
    func fact(_ k: String, count: Int) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Tokens.line)
            HStack { Text(k).foregroundStyle(Tokens.ink2); Spacer(); CountText(value: count) }.font(Tokens.text(13)).padding(.vertical, 8)
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
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text("").frame(width: 34)
                ForEach(0..<7, id: \.self) { d in
                    Text(Self.days[d]).font(Tokens.text(11.5, hover?.day == d ? .semibold : .regular))
                        .foregroundStyle(hover?.day == d ? Tokens.ink : Tokens.ink2).frame(maxWidth: .infinity)
                }
            }
            ForEach(8..<20, id: \.self) { h in
                HStack(spacing: 2) {
                    Text("\(h):00").font(Tokens.rounded(11.5, hover?.hour == h ? .bold : .semibold))
                        .foregroundStyle(hover?.hour == h ? Tokens.ink : Tokens.ink2).frame(width: 34, alignment: .trailing)
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
            // One line that answers the grid: the dot under the pointer, or the best hour when nothing is hovered. Beside it, what size means.
            HStack(spacing: 12) {
                Text(readout(peak))
                    .font(Tokens.text(12.5, .medium)).foregroundStyle(Tokens.ink).lineLimit(1)
                    .contentTransition(.interpolate).animation(reduceMotion ? nil : Motion.hover, value: readout(peak))
                Spacer(minLength: 8)
                Text("Less").font(Tokens.text(11.5)).foregroundStyle(Tokens.ink2)
                HStack(spacing: 5) {
                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { f in
                        Circle().fill(Tokens.accent.opacity(f == 0 ? 0.3 : 0.35 + 0.65 * sqrt(f))).frame(width: 4 + 11 * sqrt(f), height: 4 + 11 * sqrt(f)).frame(width: 15, height: 15)
                    }
                }
                Text("More").font(Tokens.text(11.5)).foregroundStyle(Tokens.ink2)
            }
            .padding(.top, 12).padding(.leading, 36)
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
        if trend != nil || best >= Rewards.notableStretch || streak.best >= 2 {
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Getting back on track").font(Tokens.text(15, .semibold)).accessibilityAddTraits(.isHeader)
                    if let t = trend {
                        Text(headline(t)).font(Tokens.rounded(19, .semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 0) {
                        if let t = trend {
                            fact("Average return this week", Rewards.duration(t.thisWeek.average))
                            if let l = t.lastWeek { fact("Average return last week", Rewards.duration(l.average)) }
                        }
                        if best >= Rewards.notableStretch { fact("Longest stretch without a slip", Rewards.duration(best)) }
                        if streak.best >= 2 { fact("Most focus days in a row", "\(streak.best)") }
                    }
                    if trend != nil {
                        Text("A return is the time from drifting to being back on task. Practice sessions and weeks with fewer than three returns are left out.")
                            .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
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
            HStack { Text(k).foregroundStyle(Tokens.ink2); Spacer(); Text(v).monospacedDigit() }.font(Tokens.text(13)).padding(.vertical, 8)
        }
    }
}
