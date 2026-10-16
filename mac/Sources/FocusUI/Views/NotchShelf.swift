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
    case today, goal, streak, week, next, parked, clock, battery, note, tray
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"; case .goal: return "Goal"; case .streak: return "Streak"; case .week: return "Week"
        case .next: return "Next step"; case .parked: return "Parked"; case .clock: return "Clock"; case .battery: return "Battery"
        case .note: return "My line"; case .tray: return "Tray"
        }
    }
    var detail: String {
        switch self {
        case .today: return "Time on task so far today."
        case .goal: return "How far you are into your daily goal."
        case .streak: return "Focus days in a row, rest days allowed."
        case .week: return "Seven days of focus as small bars."
        case .next: return "The next step you left for this project."
        case .parked: return "How many thoughts are waiting, and the latest."
        case .clock: return "The time and the date."
        case .battery: return "Charge left on this Mac."
        case .note: return "A line you write, such as a reminder."
        case .tray: return "Files waiting on the notch."
        }
    }
    var symbol: String {
        switch self {
        case .today: return "sun.max.fill"; case .goal: return "target"; case .streak: return "flame.fill"; case .week: return "chart.bar.fill"
        case .next: return "arrow.turn.down.right"; case .parked: return "tray.and.arrow.down.fill"; case .clock: return "clock.fill"
        case .battery: return "battery.75percent"; case .note: return "text.quote"; case .tray: return "tray.full.fill"
        }
    }
    var colors: [Color] {
        switch self {
        case .today: return [Color(red: 0.32, green: 0.80, blue: 0.52), Color(red: 0.10, green: 0.52, blue: 0.32)]
        case .goal: return [Color(red: 1.0, green: 0.62, blue: 0.24), Color(red: 0.88, green: 0.36, blue: 0.12)]
        case .streak: return [Color(red: 1.0, green: 0.45, blue: 0.30), Color(red: 0.86, green: 0.20, blue: 0.20)]
        case .week: return [Color(red: 0.62, green: 0.50, blue: 1.0), Color(red: 0.40, green: 0.28, blue: 0.88)]
        case .next: return [Color(red: 0.30, green: 0.78, blue: 0.86), Color(red: 0.10, green: 0.50, blue: 0.62)]
        case .parked: return [Color(red: 0.95, green: 0.78, blue: 0.30), Color(red: 0.78, green: 0.55, blue: 0.10)]
        case .clock: return [Color(red: 0.55, green: 0.58, blue: 0.66), Color(red: 0.30, green: 0.32, blue: 0.40)]
        case .battery: return [Color(red: 0.45, green: 0.85, blue: 0.40), Color(red: 0.20, green: 0.62, blue: 0.22)]
        case .note: return [Color(red: 0.95, green: 0.50, blue: 0.75), Color(red: 0.76, green: 0.26, blue: 0.56)]
        case .tray: return [Color(red: 0.40, green: 0.62, blue: 1.0), Color(red: 0.20, green: 0.36, blue: 0.92)]
        }
    }
    /// At most this many sit on home at once, so each stays readable.
    static let onHomeLimit = 2
}

/// A glass capsule under the open notch with one icon per page. The current page sits on a lighter pill that slides between them.
struct ShelfTabBar: View {
    @Bindable var model: NotchModel
    @Namespace private var ns
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases, id: \.self) { tab in
                Button { model.tab = tab } label: {
                    Image(systemName: tab.symbol).font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(model.tab == tab ? NotchView.ink : NotchView.ink2)
                        .frame(width: 30, height: 24)
                        .background {
                            if model.tab == tab { Capsule().fill(Color.white.opacity(0.16)).matchedGeometryEffect(id: "tab", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(ShelfIconStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .background {
            if reduceTransparency { Capsule().fill(Color.black.opacity(0.92)) }
            else { Capsule().fill(Color.black.opacity(0.35)).glassSurface(Capsule(), tint: .black.opacity(0.4), fallback: Color.black.opacity(0.85)) }
        }
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.1)) }
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

/// Home: the session laid out like Droppy's now-playing widget (artwork, title, a progress bar with the time on either end), a hairline,
/// then the widget you picked.
struct ShelfHome: View {
    @Bindable var c: SessionController
    @Bindable var model: NotchModel
    var tray: NotchTray
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SessionWidget(c: c, tint: tint).frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1).padding(.vertical, 2)
            SideWidgets(c: c, tray: tray).frame(width: 150)
        }
    }
}

struct SessionWidget: View {
    @Bindable var c: SessionController
    var tint: Color
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    // The session's "artwork": its ring on a deep tile, glowing while you are on task.
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.30, blue: 0.20), Color(red: 0.03, green: 0.12, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        RingGlow(on: c.ringColor == Tokens.accent, color: NotchView.accent).padding(10)
                        LiveRing(c.ringState, color: tint).frame(width: 26, height: 26)
                    }
                    .frame(width: 46, height: 46)
                    .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.08)) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.taskName).font(Tokens.text(15, .semibold)).lineLimit(1)
                        Text(c.presenceLabel).font(Tokens.text(12, .medium)).foregroundStyle(tint == NotchView.accent ? NotchView.accent : NotchView.ink2)
                            .contentTransition(.interpolate).motion(Motion.out(0.25), value: c.presenceLabel)
                    }
                    Spacer(minLength: 6)
                    LiveBars(on: c.ringColor == Tokens.accent, color: tint == NotchView.accent ? NotchView.accent : NotchView.ink2)
                }
                timeline
                // Never invisible: the notch always says that Focus is reading, and that it stays on this Mac.
                HStack(spacing: 6) {
                    Image(systemName: "eye").font(.system(size: 10, weight: .semibold))
                    Text(c.prefs.readScreen ? "Reading titles and on-screen words, on this Mac" : "Reading window titles, on this Mac")
                }
                .font(Tokens.text(11.5, .medium)).foregroundStyle(NotchView.ink2).lineLimit(1)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Timed: time gone on the left, time left on the right, as a song's. Open: the clock counts up beside a bar of today's goal.
    @ViewBuilder var timeline: some View {
        let t = c.clockText()
        HStack(spacing: 10) {
            if c.mode == .timed {
                Text(SessionController.format(max(0, c.totalSeconds - c.clockSeconds()))).frame(minWidth: 40, alignment: .leading)
                ShelfTrack(fraction: c.timedProgress())
                Text("-" + t).frame(minWidth: 40, alignment: .trailing)
                    .contentTransition(.numericText(countsDown: true)).motion(Motion.out(0.3), value: t)
            } else {
                Text(t).frame(minWidth: 40, alignment: .leading)
                    .contentTransition(.numericText()).motion(Motion.out(0.3), value: t)
                ShelfTrack(fraction: goalFraction ?? 0)
                Text(goalTarget ?? "Open").frame(minWidth: 40, alignment: .trailing)
            }
        }
        .font(Tokens.text(11.5, .medium)).monospacedDigit().foregroundStyle(NotchView.ink2)
    }

    var goalFraction: Double? {
        guard c.prefs.showProgress, c.prefs.dailyGoalMinutes > 0 else { return nil }
        return min(1, c.todayOnTaskSeconds() / (Double(c.prefs.dailyGoalMinutes) * 60))
    }
    var goalTarget: String? { goalFraction == nil ? nil : NotchView.minutes(Double(c.prefs.dailyGoalMinutes) * 60) }
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

/// Five small bars that sway while you are on task, the way a now-playing widget shows sound. Still for any other state, and
/// with Reduce Motion.
struct LiveBars: View {
    var on: Bool
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !on || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let wave = on && !reduceMotion ? (sin(t * (2.2 + Double(i) * 0.7) + Double(i)) + 1) / 2 : 0.25
                    Capsule().fill(color).frame(width: 2.5, height: 4 + 10 * wave)
                }
            }
            .frame(height: 14)
        }
        .accessibilityHidden(true)
    }
}

/// The widgets beside the session on home: the one you chose (a header with its colored icon, then its number), or two of them stacked
/// when you chose two. Nothing here is a button.
struct SideWidgets: View {
    @Bindable var c: SessionController
    var tray: NotchTray
    var body: some View {
        let chosen = c.prefs.notchWidgetList
        Group {
            if chosen.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No widgets").font(Tokens.rounded(15, .semibold))
                    Text("Pick some on the Widgets page").font(Tokens.text(11)).foregroundStyle(NotchView.ink2)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if chosen.count == 1 {
                WidgetTile(widget: chosen[0], c: c, tray: tray, compact: false)
            } else {
                VStack(alignment: .leading, spacing: 6) {
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
        VStack(alignment: .leading, spacing: compact ? 3 : 8) {
            HStack(spacing: 7) {
                WidgetIcon(widget: widget, size: compact ? 16 : 20)
                Text(widget.title).font(Tokens.text(compact ? 12 : 13.5, .semibold))
                Spacer(minLength: 0)
            }
            if !compact { Spacer(minLength: 0) }
            WidgetValue(widget: widget, c: c, tray: tray, compact: compact).transition(.blurReplace)
            if !compact { Spacer(minLength: 0) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One widget's figure and caption. `compact` is the two-up layout: smaller type, one line of caption.
struct WidgetValue: View {
    var widget: NotchWidget
    @Bindable var c: SessionController
    var tray: NotchTray
    var compact: Bool

    var body: some View {
        switch widget {
        case .today:
            stat(NotchView.minutes(c.todayOnTaskSeconds()), "on task today")
        case .goal:
            if c.prefs.dailyGoalMinutes > 0 {
                let f = min(1, c.todayOnTaskSeconds() / (Double(c.prefs.dailyGoalMinutes) * 60))
                HStack(spacing: compact ? 7 : 10) {
                    ZStack {
                        Circle().stroke(NotchView.track, lineWidth: compact ? 3 : 4)
                        Circle().trim(from: 0, to: f).stroke(NotchView.accent, style: StrokeStyle(lineWidth: compact ? 3 : 4, lineCap: .round)).rotationEffect(.degrees(-90))
                            .animation(Motion.out(0.6), value: f)
                    }.frame(width: compact ? 24 : 34, height: compact ? 24 : 34)
                    stat("\(Int((f * 100).rounded()))%", "of \(NotchView.minutes(Double(c.prefs.dailyGoalMinutes) * 60))")
                }
            } else {
                stat("No goal", "Set one in Rhythm and goals")
            }
        case .streak:
            let s = Rewards.streak(c.store?.sessions ?? [], today: .now)
            stat(s.current == 0 ? "None yet" : "\(s.current) \(s.current == 1 ? "day" : "days")", s.best > s.current ? "best \(s.best)" : "focus days in a row")
        case .week:
            let days = DayStats.week(c.store?.sessions ?? [], endingOn: .now)
            VStack(alignment: .leading, spacing: 3) {
                MiniWeek(days: days, height: compact ? 18 : 30)
                if !compact { Text("\(NotchView.minutes(days.reduce(0) { $0 + $1.hours } * 3600)) this week").font(Tokens.text(11)).foregroundStyle(NotchView.ink2).lineLimit(1) }
            }
        case .next:
            let step = c.projectId.flatMap { c.store?.project($0)?.nextStep } ?? ""
            if step.isEmpty { stat("None set", "Set one from the menu bar") }
            else { Text(step).font(Tokens.text(compact ? 12 : 13.5, .medium)).lineLimit(compact ? 2 : 3).fixedSize(horizontal: false, vertical: true) }
        case .parked:
            let n = c.store?.thoughts.filter { !$0.completed }.count ?? 0
            stat(n == 0 ? "Nothing" : "\(n) \(n == 1 ? "thought" : "thoughts")", c.store?.thoughts.last(where: { !$0.completed })?.text ?? "waiting")
        case .clock:
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                stat(ctx.date.formatted(date: .omitted, time: .shortened), ctx.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            }
        case .battery:
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                if let b = BatteryReader.read() { stat("\(b.percent)%", b.charging ? "charging" : (b.pluggedIn ? "plugged in" : "on battery")) }
                else { stat("No battery", "This Mac is plugged in") }
            }
        case .note:
            let t = c.prefs.notchNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { stat("Your line", "Write one in Settings, Notch") }
            else { Text(t).font(Tokens.rounded(compact ? 12.5 : 15, .semibold)).lineLimit(compact ? 2 : 4).fixedSize(horizontal: false, vertical: true) }
        case .tray:
            if tray.items.isEmpty { stat("Empty", "Drop files on the notch") }
            else { stat("\(tray.items.count) \(tray.items.count == 1 ? "file" : "files")", tray.items.last?.name ?? "") }
        }
    }

    func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 2) {
            Text(value).font(Tokens.rounded(compact ? 15 : 20, .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(caption).font(Tokens.text(compact ? 10.5 : 11)).foregroundStyle(NotchView.ink2).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// Seven days as slim bars on the notch: they grow up in turn when the notch opens, today in the accent and the rest softer.
struct MiniWeek: View {
    var days: [(day: Date, hours: Double)]
    var height: CGFloat
    var body: some View {
        let top = max(1, days.map(\.hours).max() ?? 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let today = i == days.count - 1
                Capsule().fill(today ? NotchView.accent : Color.white.opacity(d.hours > 0 ? 0.5 : 0.14))
                    .frame(width: 10, height: max(3, height * d.hours / top))
                    .modifier(GrowIn(index: i))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityLabel("Focus hours, last seven days")
    }
}

/// A widget's app-icon-like tile: its symbol in white on a glossy gradient square.
struct WidgetIcon: View {
    var widget: NotchWidget
    var size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: widget.colors, startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: widget.symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: size * 0.03, y: size * 0.02)
            }
            .overlay { RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(Color.white.opacity(0.18)) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The widgets page: every widget as a big icon, like a launcher. Tap to put one on home (up to two; a third replaces the one that has
/// been there longest) and tap again to take it off. It stays on this page so a second pick is one more tap.
struct ShelfWidgets: View {
    @Bindable var c: SessionController
    @State private var hovered: NotchWidget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
    var body: some View {
        let on = c.prefs.notchWidgetList
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(NotchWidget.allCases) { w in
                    Button { withAnimation(reduceMotion ? nil : Motion.notchSettle) { c.prefs.toggleNotchWidget(w) } } label: {
                        VStack(spacing: 4) {
                            WidgetIcon(widget: w, size: 40)
                                .overlay(alignment: .bottomTrailing) {
                                    if on.contains(w) {
                                        Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, NotchView.accent).font(.system(size: 14)).offset(x: 5, y: 5)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .scaleEffect(hovered == w && !reduceMotion ? 1.07 : 1)
                            Text(w.title).font(Tokens.text(11, .semibold)).foregroundStyle(on.contains(w) ? NotchView.ink : NotchView.ink2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ShelfIconStyle())
                    .onHover { hovered = $0 ? w : (hovered == w ? nil : hovered) }
                    .help(w.detail)
                    .accessibilityLabel("\(w.title): \(w.detail)")
                    .accessibilityValue(on.contains(w) ? "On home" : "Off")
                    .accessibilityAddTraits(on.contains(w) ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .motion(Motion.notchPress, value: hovered)
        .help("Up to two widgets show on Home. Turning on a third replaces the one that has been there longest.")
    }
}
