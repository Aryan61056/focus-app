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
            VStack(alignment: .leading, spacing: Space.xl) {
                if t.total == 0 {
                    EmptyState(symbol: "chart.bar", title: "Nothing to show yet", text: "Insights appear after your first session. Start one from Today.")
                } else {
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
                Text("How Focus reads you").font(Tokens.text(.callout, .semibold))
            }.accessibilityAddTraits(.isHeader)
            ReadingSplit(stats: t)
            HStack(spacing: Space.l) { legend("On task", t.onTask); legend("Not sure", t.unsure); legend("Off topic", t.offTask) }
            Text(a.answered == 0 ? "Answer moments in Review to compare its calls with yours." : "From \(a.answered) Review answers, a small sample.")
                .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }

    func readingFacts(_ t: ReadStats) -> some View {
        VStack(spacing: 0) {
            fact("Readings", "\(t.total)")
            fact("Read by the model", "\(t.model)")
            fact("Settled by your rules", "\(t.rule)")
            if t.skipped > 0 { fact("Left alone (never-judged list)", "\(t.skipped)") }
            fact("Sessions", "\(store.sessions.count)")
        }
    }

    func legend(_ t: String, _ n: Int) -> some View { Text("\(n) \(t.lowercased())").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
    func fact(_ k: String, _ v: String) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Tokens.line)
            HStack { Text(k).foregroundStyle(Tokens.ink2); Spacer(); Text(v).monospacedDigit() }.font(Tokens.text(.body)).padding(.vertical, Space.xs)
        }
    }
}

/// Hours 8 to 19 down, Monday to Sunday across. Darkness is on-task time; the figure is in the accessibility label.
struct Heatmap: View {
    var grid: [[Double]]
    var body: some View {
        let peak = max(grid.flatMap { $0 }.max() ?? 1, 1)
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        // The hour column grows with the Text size setting, so "10:00" never breaks.
        let labelWidth = 36 * TextScale.shared.factor
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text("").frame(width: labelWidth)
                ForEach(days, id: \.self) { Text($0).font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2).frame(maxWidth: .infinity) }
            }
            ForEach(8..<20, id: \.self) { h in
                HStack(spacing: 3) {
                    Text("\(h):00").font(Tokens.rounded(.caption2)).foregroundStyle(Tokens.ink2).lineLimit(1).frame(width: labelWidth, alignment: .trailing)
                    ForEach(0..<7, id: \.self) { d in
                        let v = grid[d][h]
                        RoundedRectangle(cornerRadius: Tokens.radiusTiny).fill(Tokens.control).overlay { RoundedRectangle(cornerRadius: Tokens.radiusTiny).fill(Tokens.accent.opacity(0.15 + 0.85 * v / peak)).opacity(v > 0 ? 1 : 0) }
                            .frame(height: 16)
                            .accessibilityElement().accessibilityLabel("\(days[d]) \(h):00, \(Int(v / 60)) minutes on task")
                    }
                }
            }
        }
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
