import SwiftUI
import FocusBrain

/// The open notch's pages, switched by the glass tab bar that hangs under it, as Droppy's shelf does (owner, 2026-10-14:
/// "exactly like Droppy"): home (the session and one widget), the file tray, and the widgets you can put on home.
public enum NotchTab: String, CaseIterable, Sendable { case home, tray, widgets
    var symbol: String { switch self { case .home: return "house.fill"; case .tray: return "tray.fill"; case .widgets: return "square.grid.2x2.fill" } }
    var title: String { switch self { case .home: return "Home"; case .tray: return "Tray"; case .widgets: return "Widgets" } }
}

/// What sits beside the session on home. Chosen on the widgets page; read only, like everything in the notch.
public enum NotchWidget: String, CaseIterable, Sendable { case today, goal, tray
    var title: String { switch self { case .today: return "Today"; case .goal: return "Goal"; case .tray: return "Tray" } }
    var symbol: String { switch self { case .today: return "sun.max"; case .goal: return "target"; case .tray: return "tray.full" } }
}

/// Three small icons in the open card's top band, one per page. The current page sits on a lighter pill that slides between them.
struct ShelfTabBar: View {
    @Bindable var model: NotchModel
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases, id: \.self) { tab in
                Button { model.tab = tab } label: {
                    Image(systemName: tab.symbol).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(model.tab == tab ? NotchView.ink : NotchView.ink2)
                        .frame(width: 26, height: 22)
                        .background {
                            if model.tab == tab { Capsule().fill(Color.white.opacity(0.16)).matchedGeometryEffect(id: "tab", in: ns) }
                        }
                        .frame(height: 24)
                        .contentShape(Capsule())
                }
                .buttonStyle(ShelfIconStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                .help(tab.title)
            }
        }
        .padding(1)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .motion(Motion.notchPeek, value: model.tab)
    }
}

/// Icons in the notch give a little under the click.
struct ShelfIconStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(reduceMotion ? nil : Motion.notchPress, value: configuration.isPressed)
    }
}

/// Home: the task and its clock over one thin bar, a hairline, then the one number you picked on the widgets page.
struct ShelfHome: View {
    @Bindable var c: SessionController
    @Bindable var model: NotchModel
    var tray: NotchTray
    var tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SessionWidget(c: c).frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1).padding(.vertical, 4)
            SideWidget(c: c, model: model, tray: tray).frame(width: 84, alignment: .leading)
        }
    }
}

struct SessionWidget: View {
    @Bindable var c: SessionController
    var body: some View {
        TimelineView(.everySecond) { _ in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(c.taskName).font(Tokens.fixed(.body, .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(c.clockText()).font(Tokens.fixed(.title3, .semibold, rounded: true)).monospacedDigit().fixedSize()
                }
                if let fraction { ShelfTrack(fraction: fraction) }
                // Never invisible: the open notch says what Focus reads. The whole sentence is the tooltip and VoiceOver's.
                HStack(spacing: 5) {
                    Image(systemName: "eye").font(.system(size: 9, weight: .semibold))
                    Text(c.prefs.readScreen ? "Titles and screen" : "Window titles")
                    Spacer(minLength: 4)
                    if let target { Text(target).monospacedDigit() }
                }
                .font(Tokens.fixed(.caption2, .medium)).foregroundStyle(NotchView.ink2).lineLimit(1)
                .help(reading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(reading)
    }

    var reading: String { c.prefs.readScreen ? "Reading window titles and on-screen words, on this Mac" : "Reading window titles, on this Mac" }

    /// Timed: how much of the session is gone. Open: today's time on task against the goal, when there is one.
    var fraction: Double? {
        if c.mode == .timed { return c.timedProgress() }
        guard c.prefs.showProgress, c.prefs.dailyGoalMinutes > 0 else { return nil }
        return min(1, c.todayOnTaskSeconds() / (Double(c.prefs.dailyGoalMinutes) * 60))
    }
    /// What the bar fills toward: the session's length, or the daily goal.
    var target: String? {
        if c.mode == .timed { return "of " + SessionController.format(c.totalSeconds) }
        return fraction == nil ? nil : "goal " + NotchView.minutes(Double(c.prefs.dailyGoalMinutes) * 60)
    }
}

/// A thin bar that fills from empty each time the notch opens.
struct ShelfTrack: View {
    var fraction: Double
    @State private var filled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Capsule().fill(NotchView.track).frame(height: 4).overlay(alignment: .leading) {
            GeometryReader { r in
                Capsule().fill(Color.white.opacity(0.85)).frame(width: max(4, r.size.width * (filled || reduceMotion ? fraction : 0)))
            }
        }
        .animation(Motion.out(0.6).delay(0.16), value: filled)
        .animation(Motion.out(0.4), value: fraction)
        .onAppear { filled = true }
    }
}

/// The widget beside the session on home: its name, then its one number.
struct SideWidget: View {
    @Bindable var c: SessionController
    @Bindable var model: NotchModel
    var tray: NotchTray
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if model.widget == .goal, let f = goalFraction { MiniRing(fraction: f).frame(width: 10, height: 10) }
                else { Image(systemName: model.widget.symbol).font(.system(size: 9, weight: .semibold)) }
                Text(model.widget.title)
            }
            .font(Tokens.fixed(.caption2, .semibold)).foregroundStyle(NotchView.ink2)
            Group {
                switch model.widget {
                case .today: stat(NotchView.minutes(c.todayOnTaskSeconds()), "on task")
                case .goal:
                    if c.prefs.dailyGoalMinutes > 0 { stat(NotchView.minutes(c.todayOnTaskSeconds()), "of " + NotchView.minutes(Double(c.prefs.dailyGoalMinutes) * 60)) }
                    else { stat("None", "set in Settings") }
                case .tray:
                    if tray.items.isEmpty { stat("Empty", "drop files here") }
                    else { stat("\(tray.items.count) \(tray.items.count == 1 ? "file" : "files")", tray.items.last?.name ?? "") }
                }
            }
            .transition(.blurReplace)
        }
        .motion(Motion.notchSettle, value: model.widget)
        .accessibilityElement(children: .combine)
    }

    var goalFraction: Double? {
        guard c.prefs.dailyGoalMinutes > 0 else { return nil }
        return min(1, c.todayOnTaskSeconds() / (Double(c.prefs.dailyGoalMinutes) * 60))
    }

    func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Tokens.fixed(.callout, .semibold, rounded: true)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(Tokens.fixed(.caption2, .regular)).foregroundStyle(NotchView.ink2).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// The goal's progress as a small ring, in the notch's accent.
struct MiniRing: View {
    var fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(NotchView.track, lineWidth: 2)
            Circle().trim(from: 0, to: fraction).stroke(NotchView.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// A widget's icon: its symbol on a quiet tile, in the notch's own grays. The chosen one takes the accent.
struct WidgetIcon: View {
    var widget: NotchWidget
    var size: CGFloat
    var chosen = false
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color.white.opacity(chosen ? 0.14 : 0.07))
            .overlay {
                Image(systemName: widget.symbol).font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(chosen ? NotchView.accent : NotchView.ink)
            }
            .overlay { RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(chosen ? NotchView.accent.opacity(0.6) : Color.white.opacity(0.08)) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The widgets page: three icons in a row. Picking one puts it on home beside the session and goes back there.
struct ShelfWidgets: View {
    @Bindable var model: NotchModel
    @State private var hovered: NotchWidget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 22) {
            ForEach(NotchWidget.allCases, id: \.self) { w in
                Button { model.widget = w; model.tab = .home } label: {
                    VStack(spacing: 6) {
                        WidgetIcon(widget: w, size: 38, chosen: model.widget == w)
                            .scaleEffect(hovered == w && !reduceMotion ? 1.06 : 1)
                        Text(w.title).font(Tokens.fixed(.caption2, .medium)).foregroundStyle(model.widget == w ? NotchView.ink : NotchView.ink2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ShelfIconStyle())
                .onHover { hovered = $0 ? w : (hovered == w ? nil : hovered) }
                .accessibilityLabel("Show \(w.title) on home")
                .accessibilityAddTraits(model.widget == w ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .motion(Motion.notchPress, value: hovered)
        .motion(Motion.notchSettle, value: model.widget)
    }
}
