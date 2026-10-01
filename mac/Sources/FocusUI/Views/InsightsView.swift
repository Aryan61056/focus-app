import SwiftUI

/// First native slice of Insights: how well Focus is reading you, from saved counts and your own Review answers.
/// The hours-by-day charts from the design board come later.
struct InsightsView: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore

    var body: some View {
        let t = store.readTotals
        let a = store.agreement
        Scroller {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Insights").font(Tokens.rounded(26, .semibold))
                    Text("Worked out on this Mac from your own sessions.").font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2)
                }
                if t.total == 0 {
                    EmptyState(title: "Nothing to show yet", text: "After a session, this shows what Focus read, how often it was sure, and how often you agreed with it.")
                } else {
                    if let share = DayStats.morningShare(DayStats.heat(store.sessions)) {
                        Text("Mornings are your strongest time: \(share)% of your focused minutes fall before noon.").font(Tokens.rounded(19, .semibold)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 620, alignment: .leading)
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) { Text("When you focus").font(Tokens.text(15, .semibold)); Spacer(); Text("on-task time by hour and day").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
                            Heatmap(grid: DayStats.heat(store.sessions))
                        }
                    }
                    .frame(maxWidth: 560)
                    Panel {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("How well Focus is reading you").font(Tokens.text(15, .semibold)).accessibilityAddTraits(.isHeader)
                            Text(a.answered == 0 ? "You have not answered any Review moments yet, so there is nothing to compare with." : "You agreed with \(a.agreed) of \(a.answered) calls.")
                                .font(Tokens.rounded(19, .semibold))
                            ReadingSplit(stats: t)
                            HStack(spacing: 18) { legend("On task", t.onTask); legend("Not sure", t.unsure); legend("Off topic", t.offTask) }
                            VStack(spacing: 0) {
                                fact("Readings", "\(t.total)")
                                fact("Read by the model", "\(t.model)")
                                fact("Settled by your rules", "\(t.rule)")
                                if t.skipped > 0 { fact("Left alone (never-judged list)", "\(t.skipped)") }
                                fact("Sessions", "\(store.sessions.count)")
                            }
                            Text(a.answered == 0 ? "Answers in Review show whether Focus's calls match yours." : "The agreement figure counts only the \(a.answered) answers you gave in Review. That is a small sample, so read it loosely.")
                                .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: 560)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }.scrollIndicators(.hidden)
    }

    func legend(_ t: String, _ n: Int) -> some View { Text("\(t) \(n)").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
    func fact(_ k: String, _ v: String) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Tokens.line)
            HStack { Text(k).foregroundStyle(Tokens.ink2); Spacer(); Text(v).monospacedDigit() }.font(Tokens.text(13)).padding(.vertical, 8)
        }
    }
}

/// Hours 8 to 19 down, Monday to Sunday across. Darkness is on-task time; the figure is in the accessibility label.
struct Heatmap: View {
    var grid: [[Double]]
    var body: some View {
        let peak = max(grid.flatMap { $0 }.max() ?? 1, 1)
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text("").frame(width: 34)
                ForEach(days, id: \.self) { Text($0).font(Tokens.text(11.5)).foregroundStyle(Tokens.ink2).frame(maxWidth: .infinity) }
            }
            ForEach(8..<20, id: \.self) { h in
                HStack(spacing: 3) {
                    Text("\(h):00").font(Tokens.rounded(11.5)).foregroundStyle(Tokens.ink2).frame(width: 34, alignment: .trailing)
                    ForEach(0..<7, id: \.self) { d in
                        let v = grid[d][h]
                        RoundedRectangle(cornerRadius: 4).fill(Tokens.control).overlay { RoundedRectangle(cornerRadius: 4).fill(Tokens.accent.opacity(0.15 + 0.85 * v / peak)).opacity(v > 0 ? 1 : 0) }
                            .frame(height: 16)
                            .accessibilityElement().accessibilityLabel("\(days[d]) \(h):00, \(Int(v / 60)) minutes on task")
                    }
                }
            }
        }
    }
}
