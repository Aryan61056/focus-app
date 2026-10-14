import SwiftUI
import FocusBrain

/// A plain bar with the goal in words beside it. Shape and text carry the state; the fill is accent, the track is neutral.
struct GoalBar: View {
    var goal: Rewards.Goal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.track)
                Capsule().fill(Tokens.accent).frame(width: max(goal.fraction > 0 ? 8 : 0, g.size.width * goal.fraction))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: goal.fraction)
            }
        }
        .frame(height: 8)
        .accessibilityElement().accessibilityLabel("Daily goal").accessibilityValue("\(goal.minutes) of \(goal.goalMinutes) minutes")
    }
}

/// Seven days, oldest first. Filled with a tick = focus day, dashed ring = rest day, small dot = nothing, empty ring = today so far.
/// Never a cross or a red mark: a missed day shows as nothing or as a rest day.
struct WeekStrip: View {
    var week: [(day: Date, mark: Rewards.DayMark)]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, d in
                VStack(spacing: 5) {
                    mark(d.mark).frame(width: 20, height: 20)
                    Text(d.day.formatted(.dateTime.weekday(.narrow))).font(Tokens.text(11.5)).foregroundStyle(Tokens.ink2)
                }
                .accessibilityElement().accessibilityLabel("\(d.day.formatted(.dateTime.weekday(.wide))), \(label(d.mark))")
            }
        }
    }

    func label(_ m: Rewards.DayMark) -> String {
        switch m { case .focus: return "focus day"; case .rest: return "rest day"; case .pending: return "today, not yet a focus day"; case .none: return "no session" }
    }

    @ViewBuilder func mark(_ m: Rewards.DayMark) -> some View {
        switch m {
        case .focus:
            ZStack { Circle().fill(Tokens.accent); Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Tokens.onAccent) }
        case .rest:
            Circle().strokeBorder(Tokens.accent, style: StrokeStyle(lineWidth: 1.6, dash: [2.5, 2.5]))
        case .pending:
            Circle().strokeBorder(Tokens.ink2, lineWidth: 1.6)
        case .none:
            Circle().fill(Tokens.track).frame(width: 6, height: 6)
        }
    }
}

/// A short line while working: back on task quickly, goal reached, longest stretch. Gone after a few seconds, never a popup.
struct MomentLine: View {
    var moment: Confirmation
    var body: some View {
        HStack(spacing: 8) {
            RingView(.done, color: Tokens.accent).frame(width: 16, height: 16)
            Text(moment.text).font(Tokens.text(13, .semibold))
        }
        .padding(.leading, 8).padding(.trailing, 12).frame(height: 28)
        .background(Capsule().fill(Tokens.accentSoft))
        .transition(.opacity)
        .accessibilityElement(children: .ignore).accessibilityLabel(moment.text)
    }
}

/// The one line about a session that just ended (see Rewards.highlight). Kind when it was rough, plain when it was short.
struct HighlightLine: View {
    var highlight: Rewards.Highlight
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            RingView(highlight == .rough ? .paused : .done, color: highlight == .rough ? Tokens.ink2 : Tokens.accent).frame(width: 14, height: 14)
            Text(Rewards.text(highlight)).font(Tokens.text(14, .medium)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
