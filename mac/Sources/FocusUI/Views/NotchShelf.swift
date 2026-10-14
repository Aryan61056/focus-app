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
    var symbol: String { switch self { case .today: return "sun.max.fill"; case .goal: return "target"; case .tray: return "tray.full.fill" } }
    var colors: [Color] {
        switch self {
        case .today: return [Color(red: 0.32, green: 0.80, blue: 0.52), Color(red: 0.10, green: 0.52, blue: 0.32)]
        case .goal: return [Color(red: 1.0, green: 0.62, blue: 0.24), Color(red: 0.88, green: 0.36, blue: 0.12)]
        case .tray: return [Color(red: 0.40, green: 0.62, blue: 1.0), Color(red: 0.20, green: 0.36, blue: 0.92)]
        }
    }
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
            SideWidget(c: c, model: model, tray: tray).frame(width: 150)
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

/// The widget beside the session on home: a header with its colored icon, then its one number.
struct SideWidget: View {
    @Bindable var c: SessionController
    @Bindable var model: NotchModel
    var tray: NotchTray
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                WidgetIcon(widget: model.widget, size: 20)
                Text(model.widget.title).font(Tokens.text(13.5, .semibold))
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Group {
                switch model.widget {
                case .today:
                    stat(NotchView.minutes(c.todayOnTaskSeconds()), "on task today")
                case .goal:
                    if c.prefs.dailyGoalMinutes > 0 {
                        let f = min(1, c.todayOnTaskSeconds() / (Double(c.prefs.dailyGoalMinutes) * 60))
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().stroke(NotchView.track, lineWidth: 4)
                                Circle().trim(from: 0, to: f).stroke(NotchView.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                            }.frame(width: 34, height: 34)
                            stat("\(Int((f * 100).rounded()))%", "of \(NotchView.minutes(Double(c.prefs.dailyGoalMinutes) * 60))")
                        }
                    } else {
                        stat("No goal", "Set one in Rhythm and goals")
                    }
                case .tray:
                    if tray.items.isEmpty {
                        stat("Empty", "Drop files on the notch")
                    } else {
                        stat("\(tray.items.count) \(tray.items.count == 1 ? "file" : "files")", tray.items.last?.name ?? "")
                    }
                }
            }
            .transition(.blurReplace)
            Spacer(minLength: 0)
        }
        .motion(Motion.notchSettle, value: model.widget)
        .accessibilityElement(children: .combine)
    }

    func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Tokens.rounded(20, .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(Tokens.text(11)).foregroundStyle(NotchView.ink2).lineLimit(1).truncationMode(.middle)
        }
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

/// The widgets page: big icons in a row, like a launcher. Picking one puts it on home beside the session and goes back there.
struct ShelfWidgets: View {
    @Bindable var model: NotchModel
    @State private var hovered: NotchWidget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 26) {
            ForEach(NotchWidget.allCases, id: \.self) { w in
                Button { model.widget = w; model.tab = .home } label: {
                    VStack(spacing: 7) {
                        WidgetIcon(widget: w, size: 52)
                            .overlay(alignment: .bottomTrailing) {
                                if model.widget == w {
                                    Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, NotchView.accent).font(.system(size: 15)).offset(x: 5, y: 5)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .scaleEffect(hovered == w && !reduceMotion ? 1.06 : 1)
                        Text(w.title).font(Tokens.text(11.5, .semibold)).foregroundStyle(NotchView.ink)
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
