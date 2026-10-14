import SwiftUI
import Charts
import FocusLinkNet

/// Seven days of on-task time. A rest day is shown as a rest, never as a miss, the same as on the Mac.
struct WeekCard: View {
    let insights: Insights

    private var focusDays: Int { insights.week.filter { $0.mark == .focus }.count }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Eyebrow("This week")
                    Spacer()
                    if insights.streak > 1 { Label("\(insights.streak) focus days in a row", systemImage: "leaf").font(.footnote.weight(.medium)).foregroundStyle(Palette.accent) }
                }
                Chart(insights.week) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Hours", day.onTaskSeconds / 3600), width: .ratio(0.55))
                        .foregroundStyle(day.mark == .focus ? Palette.accent : Palette.track)
                        .clipShape(.rect(cornerRadius: 6))
                    if insights.goalMinutes > 0 {
                        RuleMark(y: .value("Goal", Double(insights.goalMinutes) / 60))
                            .foregroundStyle(Palette.ink2.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(Palette.ink2) } }
                .chartYAxis(.hidden)
                .frame(height: 130)
                .accessibilityLabel("On-task time for the last seven days")
                .accessibilityValue("\(focusDays) focus days")
                if insights.restDaysUsed > 0 {
                    Text("\(insights.restDaysUsed) rest \(insights.restDaysUsed == 1 ? "day" : "days") this week. They don't break anything.")
                        .font(.footnote).foregroundStyle(Palette.ink2)
                }
            }
        }
    }
}
