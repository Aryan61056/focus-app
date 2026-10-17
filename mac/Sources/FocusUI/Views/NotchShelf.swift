import SwiftUI
import FocusBrain

/// The open notch's pages, switched by the glass tab bar that hangs under it, as Droppy's shelf does (owner, 2026-10-14:
/// "exactly like Droppy"): home (the session and one widget), the file tray, and the widgets you can put on home.
public enum NotchTab: String, CaseIterable, Sendable { case home, tray, widgets
    var symbol: String { switch self { case .home: return "house.fill"; case .tray: return "tray.fill"; case .widgets: return "square.grid.2x2.fill" } }
    var title: String { switch self { case .home: return "Home"; case .tray: return "Tray"; case .widgets: return "Widgets" } }
}

/// What can sit beside the session on home. Chosen on the widgets page or in Settings; read only, like everything in the notch.
/// Everything here is worked out on this Mac from what Focus already keeps; nothing is fetched.
public enum NotchWidget: String, CaseIterable, Identifiable, Sendable {
    case today, goal, streak, week, parked, clock, battery, note, tray
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"; case .goal: return "Goal"; case .streak: return "Streak"; case .week: return "Week"
        case .parked: return "Parked"; case .clock: return "Clock"; case .battery: return "Battery"
        case .note: return "My line"; case .tray: return "Tray"
        }
    }
    var detail: String {
        switch self {
        case .today: return "Time on task so far today."
        case .goal: return "How far you are into your daily goal."
        case .streak: return "Focus days in a row, rest days allowed."
        case .week: return "Seven days of focus as small bars."
        case .parked: return "How many thoughts are waiting, and the latest."
        case .clock: return "The time and the date."
        case .battery: return "Charge left on this Mac."
        case .note: return "A line you write, such as a reminder."
        case .tray: return "Files waiting on the notch."
        }
    }
    var symbol: String {
        switch self {
        case .today: return "sun.max"; case .goal: return "target"; case .streak: return "flame"; case .week: return "chart.bar"
        case .parked: return "tray.and.arrow.down"; case .clock: return "clock"
        case .battery: return "battery.75percent"; case .note: return "text.quote"; case .tray: return "tray.full"
        }
    }
    /// At most this many sit on home at once, so each stays readable.
    static let onHomeLimit = 2
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
            SideWidgets(c: c, tray: tray).frame(width: 104, alignment: .leading)
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

/// The widgets beside the session on home: the one you chose (its name, then its number), or two of them stacked when you chose two.
/// Nothing here is a button.
struct SideWidgets: View {
    @Bindable var c: SessionController
    var tray: NotchTray
    var body: some View {
        let chosen = c.prefs.notchWidgetList
        Group {
            if chosen.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text("No widgets").font(Tokens.fixed(.callout, .semibold, rounded: true))
                    Text("pick some on Widgets").font(Tokens.fixed(.caption2, .regular)).foregroundStyle(NotchView.ink2).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else if chosen.count == 1 {
                WidgetTile(widget: chosen[0], c: c, tray: tray, compact: false)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    WidgetTile(widget: chosen[0], c: c, tray: tray, compact: true)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    WidgetTile(widget: chosen[1], c: c, tray: tray, compact: true)
                }
            }
        }
        .motion(Motion.notchSettle, value: chosen)
    }
}

struct WidgetTile: View {
    var widget: NotchWidget
    @Bindable var c: SessionController
    var tray: NotchTray
    var compact: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 4) {
            HStack(spacing: 5) {
                if widget == .goal, let f = goalFraction { MiniRing(fraction: f).frame(width: 10, height: 10) }
                else { Image(systemName: widget.symbol).font(.system(size: 9, weight: .semibold)) }
                Text(widget.title)
            }
            .font(Tokens.fixed(.caption2, .semibold)).foregroundStyle(NotchView.ink2)
            WidgetValue(widget: widget, c: c, tray: tray, compact: compact).transition(.blurReplace)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .help(widget.detail)
    }
    var goalFraction: Double? {
        guard c.prefs.dailyGoalMinutes > 0 else { return nil }
        return min(1, c.todayOnTaskSeconds() / (Double(c.prefs.dailyGoalMinutes) * 60))
    }
}

/// One widget's figure and caption. `compact` is the two-up layout: the figure alone, since the card has room for two lines each.
struct WidgetValue: View {
    var widget: NotchWidget
    @Bindable var c: SessionController
    var tray: NotchTray
    var compact: Bool

    var body: some View {
        switch widget {
        case .today:
            stat(NotchView.minutes(c.todayOnTaskSeconds()), "on task")
        case .goal:
            if c.prefs.dailyGoalMinutes > 0 { stat(NotchView.minutes(c.todayOnTaskSeconds()), "of " + NotchView.minutes(Double(c.prefs.dailyGoalMinutes) * 60)) }
            else { stat("None", "set in Settings") }
        case .streak:
            let s = Rewards.streak(c.store?.sessions ?? [], today: .now)
            stat(s.current == 0 ? "None yet" : "\(s.current) \(s.current == 1 ? "day" : "days")", s.best > s.current ? "best \(s.best)" : "in a row")
        case .week:
            let days = DayStats.week(c.store?.sessions ?? [], endingOn: .now)
            VStack(alignment: .leading, spacing: 2) {
                MiniWeek(days: days, height: compact ? 14 : 28)
                if !compact { Text("\(NotchView.minutes(days.reduce(0) { $0 + $1.hours } * 3600)) this week").font(Tokens.fixed(.caption2, .regular)).foregroundStyle(NotchView.ink2).lineLimit(1) }
            }
        case .parked:
            let n = c.store?.thoughts.filter { !$0.completed }.count ?? 0
            stat(n == 0 ? "Nothing" : "\(n) \(n == 1 ? "thought" : "thoughts")", c.store?.thoughts.last(where: { !$0.completed })?.text ?? "waiting")
        case .clock:
            TimelineView(.everySecond) { ctx in
                stat(ctx.date.formatted(date: .omitted, time: .shortened), ctx.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            }
        case .battery:
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                if let b = BatteryReader.read() { stat("\(b.percent)%", b.charging ? "charging" : (b.pluggedIn ? "plugged in" : "on battery")) }
                else { stat("No battery", "plugged in") }
            }
        case .note:
            let t = c.prefs.notchNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { stat("Your line", "write one in Settings") }
            else { Text(t).font(Tokens.fixed(compact ? .caption : .callout, .semibold, rounded: true)).lineLimit(compact ? 1 : 3).fixedSize(horizontal: false, vertical: true) }
        case .tray:
            if tray.items.isEmpty { stat("Empty", "drop files here") }
            else { stat("\(tray.items.count) \(tray.items.count == 1 ? "file" : "files")", tray.items.last?.name ?? "") }
        }
    }

    func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Tokens.fixed(.callout, .semibold, rounded: true)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if !compact { Text(caption).font(Tokens.fixed(.caption2, .regular)).foregroundStyle(NotchView.ink2).lineLimit(1).truncationMode(.middle) }
        }
    }
}

/// Seven days as slim bars on the notch: they grow up in turn when the notch opens, today in the accent and the rest softer.
struct MiniWeek: View {
    var days: [(day: Date, hours: Double)]
    var height: CGFloat
    var body: some View {
        let top = max(1, days.map(\.hours).max() ?? 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let today = i == days.count - 1
                Capsule().fill(today ? NotchView.accent : Color.white.opacity(d.hours > 0 ? 0.5 : 0.14))
                    .frame(width: 8, height: max(3, height * d.hours / top))
                    .modifier(GrowIn(index: i))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityLabel("Focus hours, last seven days")
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

/// The widgets page: every widget as an icon. Tap to put one on home (up to two; a third replaces the one that has been there longest)
/// and tap again to take it off. It stays on this page so a second pick is one more tap.
struct ShelfWidgets: View {
    @Bindable var c: SessionController
    @State private var hovered: NotchWidget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
    var body: some View {
        let on = c.prefs.notchWidgetList
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(NotchWidget.allCases) { w in
                Button { withAnimation(reduceMotion ? nil : Motion.notchSettle) { c.prefs.toggleNotchWidget(w) } } label: {
                    WidgetIcon(widget: w, size: 30, chosen: on.contains(w))
                        .scaleEffect(hovered == w && !reduceMotion ? 1.07 : 1)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ShelfIconStyle())
                .onHover { hovered = $0 ? w : (hovered == w ? nil : hovered) }
                .help("\(w.title): \(w.detail)")
                .accessibilityLabel("\(w.title): \(w.detail)")
                .accessibilityValue(on.contains(w) ? "On home" : "Off")
                .accessibilityAddTraits(on.contains(w) ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .motion(Motion.notchPress, value: hovered)
    }
}
