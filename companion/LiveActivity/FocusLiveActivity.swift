import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FocusWidgets: WidgetBundle {
    var body: some Widget { FocusLiveActivity() }
}

private extension FocusActivityAttributes.ContentState.Phase {
    var symbol: String {
        switch self {
        case .onTask: "checkmark.circle"
        case .unsure: "questionmark.circle"
        case .drifting: "arrow.uturn.left.circle"
        case .recovering: "arrow.trianglehead.clockwise"
        case .paused: "pause.circle"
        case .onBreak: "cup.and.saucer"
        }
    }
    var label: String {
        switch self {
        case .onTask: "On task"
        case .unsure: "Not sure"
        case .drifting: "Drifting"
        case .recovering: "Getting back"
        case .paused: "Paused"
        case .onBreak: "On a break"
        }
    }
    var tint: Color { self == .drifting ? Color(red: 0.91, green: 0.72, blue: 0.47) : self == .onTask || self == .recovering ? Color(red: 0.47, green: 0.84, blue: 0.62) : .secondary }
}

/// The session's time, drawn by the system so it keeps counting without the app running.
private struct SessionTimer: View {
    let state: FocusActivityAttributes.ContentState
    var body: some View {
        if let end = state.endsAt, end > .now { Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit() }
        else if let since = state.since { Text(since, style: .timer).monospacedDigit() }
        else { Text(Duration.seconds(state.frozenSeconds), format: .time(pattern: .minuteSecond)).monospacedDigit() }
    }
}

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.phase.symbol).font(.title).foregroundStyle(context.state.phase.tint).symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.task).font(.headline).lineLimit(1)
                    Text(context.state.phase.label).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                SessionTimer(state: context.state).font(.system(.title, design: .rounded).weight(.semibold)).multilineTextAlignment(.trailing)
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.05, green: 0.07, blue: 0.06).opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: context.state.phase.symbol).font(.title2).foregroundStyle(context.state.phase.tint) }
                DynamicIslandExpandedRegion(.trailing) { SessionTimer(state: context.state).font(.system(.title2, design: .rounded).weight(.semibold)) }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.task).font(.headline).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.phase.label).font(.subheadline).foregroundStyle(.secondary) }
            } compactLeading: {
                Image(systemName: context.state.phase.symbol).foregroundStyle(context.state.phase.tint)
            } compactTrailing: {
                SessionTimer(state: context.state).frame(maxWidth: 52).font(.system(.footnote, design: .rounded).weight(.semibold))
            } minimal: {
                Image(systemName: context.state.phase.symbol).foregroundStyle(context.state.phase.tint)
            }
        }
    }
}
