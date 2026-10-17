import SwiftUI
import FocusLinkNet

struct InsightsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.canvas.ignoresSafeArea()
                ScrollView {
                    if let i = model.displayedInsights {
                        VStack(spacing: 16) {
                            if let asOf = model.insightsAsOf { AsOfNote(date: asOf) }
                            TodayCard(insights: i)
                            WeekCard(insights: i)
                            if let r = i.returnSeconds, i.returnCount > 0 { ReturnCard(seconds: r, count: i.returnCount) }
                            RecentSessions(sessions: i.recent)
                        }
                        .padding(.horizontal, Metrics.gutter).padding(.bottom, 24)
                        .frame(maxWidth: 560)
                    } else {
                        EmptyInsights().padding(.top, 80).padding(.horizontal, Metrics.gutter)
                    }
                }
            }
            .navigationTitle("Insights")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ConnectionChip() } }
        }
        .motion(Motion.settle, value: model.displayedInsights != nil)
    }
}

/// Says these numbers are from iCloud and when, so a quiet Mac is not mistaken for a quiet day.
private struct AsOfNote: View {
    let date: Date
    var body: some View {
        Label("From your Mac, \(date.formatted(.relative(presentation: .named)))", systemImage: "icloud")
            .font(.footnote).foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

private struct EmptyInsights: View {
    var body: some View {
        ContentUnavailableView {
            Label("Nothing here yet", systemImage: "chart.bar.xaxis")
        } description: {
            Text("Connect your Mac, or turn on Keep Insights in iCloud there, and finish a session. Your days and sessions show up here.")
        }
    }
}

private struct TodayCard: View {
    let insights: Insights
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize = 84

    private var goal: Double { Double(insights.goalMinutes) * 60 }
    private var progress: Double { goal > 0 ? min(1, insights.todayOnTaskSeconds / goal) : 1 }

    var body: some View {
        Card {
            HStack(spacing: 18) {
                ZStack {
                    FocusRing(phase: .onTask, progress: max(progress, 0.001), lineWidth: 9)
                    if goal > 0, progress >= 1 { Image(systemName: "checkmark").font(.title3.weight(.bold)).foregroundStyle(Palette.accent) }
                }
                .frame(width: ringSize, height: ringSize)
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow("Today")
                    Text(insights.todayOnTaskSeconds.spokenText).font(.title.weight(.semibold)).contentTransition(.numericText())
                    Text(goal > 0 ? (progress >= 1 ? "Daily goal reached" : "of your \(insights.goalMinutes) min goal") : "on task")
                        .font(.subheadline).foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ReturnCard: View {
    let seconds: Double
    let count: Int
    var body: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: "arrow.uturn.left.circle").font(.title).foregroundStyle(Palette.accent).symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("Getting back on track")
                    Text("About \(Int(seconds.rounded())) s to return").font(.headline)
                    Text("\(count) times this week").font(.subheadline).foregroundStyle(Palette.ink2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
