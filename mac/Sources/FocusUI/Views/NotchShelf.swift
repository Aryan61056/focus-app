import SwiftUI
import FocusBrain

/// The open notch's two pages, switched by the small glass pill that hangs under the card, as Droppy's does (owner, 2026-10-14:
/// "exactly like Droppy"; 2026-10-24: "exact same visuals"): home, the session and today, and the file tray. The widgets page was
/// removed on 2026-10-24 ("drop the mini app feature"): it was not finished well enough to keep.
public enum NotchTab: String, CaseIterable, Sendable { case home, tray
    var symbol: String { switch self { case .home: return "house.fill"; case .tray: return "tray.fill" } }
    var title: String { switch self { case .home: return "Home"; case .tray: return "Tray" } }
}

/// The tab pill under the open card: 29 pt tall, Droppy's size, an icon per page, the current page on a lighter capsule that slides
/// between them. It is glass where the Mac has it, a material where it does not.
struct ShelfTabPill: View {
    @Bindable var model: NotchModel
    @Namespace private var ns
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        HStack(spacing: 0) {
            ForEach(NotchTab.allCases, id: \.self) { tab in
                let on = model.tab == tab
                Button { model.tab = tab } label: {
                    Image(systemName: tab.symbol).font(.system(size: 12.5, weight: .semibold))
                        .symbolEffect(.bounce, options: .speed(1.4), value: on)
                        .foregroundStyle(on ? Color.white : Color.white.opacity(0.58))
                        .frame(width: 31, height: 23)
                        .background { if on { Capsule().fill(Color.white.opacity(0.24)).matchedGeometryEffect(id: "tab", in: ns) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(ShelfIconStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(on ? .isSelected : [])
                .help(tab.title)
            }
        }
        .padding(3)
        .frame(height: NotchLayout.pillHeight)
        .background { pillBackground }
        .motion(Motion.notchPeek, value: model.tab)
    }

    /// Frosted like Droppy's: a blur of the desktop behind it, Liquid Glass over that, and a thin light edge.
    @ViewBuilder var pillBackground: some View {
        if !reduceTransparency, #available(macOS 26, *) {
            ZStack {
                NotchBlur().clipShape(Capsule())
                Color.clear.glassEffect(.clear.tint(.white.opacity(0.06)), in: Capsule())
            }
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75) }
        } else {
            Capsule().fill(Color.black.opacity(0.78))
        }
    }
}

/// Each piece of a page arrives on its own: it rises a few points, sharpens out of a blur and settles with a spring, one after another
/// in reading order, so the card fills in as the shape opens instead of appearing all at once. Reduce Motion gets a plain fade.
struct Rise: ViewModifier {
    var index: Int
    var on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .blur(radius: on || reduceMotion ? 0 : 8)
            .offset(y: on || reduceMotion ? 0 : 12)
            .scaleEffect(on || reduceMotion ? 1 : 0.9, anchor: .top)
            .animation(reduceMotion ? Motion.reduced : Motion.notchOpen.delay(0.06 + Double(index) * 0.04), value: on)
    }
}
extension View { func rise(_ index: Int, _ on: Bool) -> some View { modifier(Rise(index: index, on: on)) } }

/// Icons in the notch give a little under the click.
struct ShelfIconStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(reduceMotion ? nil : Motion.notchPress, value: configuration.isPressed)
    }
}

/// Home, laid out as Droppy's media card is, to the point: the session where its player is, today where its widget is. The card is a
/// fixed 485 x 164 pt under the hardware notch's band, and each piece sits where Droppy puts its counterpart (measured from its window):
///
///  - the tile (Droppy's album art) holds the ring; the task is the title and how Hushd reads you is the line under it;
///  - the progress row is the session's clock: time gone, a bar, time left (or "Open" for a session with no end);
///  - the row where Droppy has its transport buttons holds read-only figures, since the notch has no controls (owner, 2026-10-13);
///  - the divider and the right pane are Droppy's widget: today's time on task as a ring against the daily goal.
///
/// Nothing on the page is a button. It says what Hushd reads, so it is never invisible.
struct ShelfHome: View {
    @Bindable var c: SessionController
    var tint: Color
    /// False for the first beat, then true: each piece rises in when the page appears (see `Rise`).
    @State private var arrived = false

    var body: some View {
        TimelineView(.everySecond) { _ in
            let counts = Counts(c.liveSegments(c.nowSeconds()))
            ZStack(alignment: .topLeading) {
                session(counts)
                Rectangle().fill(Color.white.opacity(0.16)).frame(width: 1, height: 82).offset(x: 324, y: 38)
                    .scaleEffect(y: arrived ? 1 : 0, anchor: .top).opacity(arrived ? 1 : 0)
                    .animation(Motion.out(0.5).delay(0.2), value: arrived)
                today
            }
            .frame(width: 485, height: NotchLayout.openHeight - 32, alignment: .topLeading)
        }
        .onAppear { DispatchQueue.main.async { arrived = true } }
        .onDisappear { arrived = false }
        .accessibilityElement(children: .combine)
        .accessibilityHint(reading)
    }

    var reading: String { c.prefs.readScreen ? "Reading window titles and on-screen words, on this Mac" : "Reading window titles, on this Mac" }

    // MARK: the session, where Droppy has its player

    @ViewBuilder func session(_ counts: Counts) -> some View {
        let timed = c.mode == .timed
        let left = c.clockSeconds()
        let elapsed = timed ? max(0, c.totalSeconds - left) : left
        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.09))
            .frame(width: 46.5, height: 46.5)
            .overlay { LiveRing(c.ringState, color: tint).frame(width: 24, height: 24) }
            .rise(0, arrived).offset(x: 20, y: 13)
        Text(c.taskName).font(.system(size: 15, weight: .bold)).foregroundStyle(NotchView.ink).lineLimit(1).truncationMode(.tail)
            .frame(width: 196, alignment: .leading).rise(1, arrived).offset(x: 83, y: 19)
        Text(c.presenceLabel).font(.system(size: 13, weight: .medium)).foregroundStyle(tint == NotchView.accent ? tint : NotchView.ink2).lineLimit(1)
            .contentTransition(.interpolate).frame(width: 196, alignment: .leading).rise(2, arrived).offset(x: 83, y: 41)
        Image(systemName: c.prefs.readScreen ? "eye.fill" : "eye").font(.system(size: 11, weight: .semibold)).foregroundStyle(NotchView.ink2)
            .frame(width: 21, height: 12).rise(2, arrived).offset(x: 292.5, y: 24).help(reading)

        Text(SessionController.format(elapsed)).font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(NotchView.ink2)
            .lineLimit(1).minimumScaleFactor(0.8).frame(width: 40, alignment: .leading).rise(3, arrived).offset(x: 17.5, y: 72)
        ShelfTrack(fraction: timed ? c.timedProgress() : 0).frame(width: 213).rise(3, arrived).offset(x: 59.5, y: 76.5)
        Text(timed ? SessionController.format(left) : "Open").font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(NotchView.ink2)
            .lineLimit(1).minimumScaleFactor(0.8).frame(width: 42, alignment: .trailing).rise(3, arrived).offset(x: 271.5, y: 72)

        // Where Droppy's transport row is: four read-only figures at its four positions.
        stat(Self.short(counts.on), "on task", x: 108.5, index: 4)
        stat(Self.short(counts.unsure), "not sure", x: 167.5, index: 5)
        stat(Self.short(counts.off), "off topic", x: 223, index: 6)
        VStack(spacing: 2) {
            Image(systemName: c.prefs.readScreen ? "macwindow.badge.plus" : "macwindow").font(.system(size: 17, weight: .semibold)).foregroundStyle(NotchView.ink).frame(height: 22)
            Text(c.prefs.readScreen ? "titles, screen" : "titles").font(.system(size: 9.5, weight: .medium)).foregroundStyle(NotchView.ink2).lineLimit(1)
        }
        .frame(width: 64).rise(7, arrived).offset(x: 286.5 - 32, y: 100).help(reading)
    }

    func stat(_ value: String, _ caption: String, x: CGFloat, index: Int) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(NotchView.ink).lineLimit(1).minimumScaleFactor(0.7).frame(height: 22)
                .contentTransition(.numericText()).animation(Motion.out(0.3), value: value)
            Text(caption).font(.system(size: 9.5, weight: .medium)).foregroundStyle(NotchView.ink2).lineLimit(1)
        }
        .frame(width: 56).rise(index, arrived).offset(x: x - 28, y: 100)
    }

    // MARK: today, where Droppy has its usage widget

    var goalMinutes: Double { Double(c.prefs.dailyGoalMinutes) }
    @ViewBuilder var today: some View {
        let seconds = c.todayOnTaskSeconds()
        let fraction = goalMinutes > 0 ? min(1, seconds / (goalMinutes * 60)) : 0
        ZStack(alignment: .topLeading) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max").font(.system(size: 12, weight: .semibold))
                Text("Today").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(NotchView.ink2).rise(4, arrived).offset(x: 334, y: 17)
            TodayRing(fraction: fraction, arrived: arrived).frame(width: 48, height: 48).rise(5, arrived).offset(x: 380, y: 50.5)
            Text(NotchView.minutes(seconds)).font(.system(size: 13, weight: .bold)).foregroundStyle(NotchView.ink).lineLimit(1)
                .contentTransition(.numericText()).animation(Motion.out(0.3), value: seconds)
                .frame(width: 140).rise(6, arrived).offset(x: 334, y: 100)
            Text(goalMinutes > 0 ? "of " + NotchView.minutes(goalMinutes * 60) : "on task").font(.system(size: 12, weight: .medium)).foregroundStyle(NotchView.ink2).lineLimit(1)
                .frame(width: 140).rise(7, arrived).offset(x: 334, y: 115)
        }
    }

    /// "42s", "12m", "1h 5m": figures that fit a 56 pt slot.
    static func short(_ s: Double) -> String {
        let n = Int(s)
        if n < 60 { return "\(n)s" }
        if n < 3600 { return "\(n / 60)m" }
        return n % 3600 < 60 ? "\(n / 3600)h" : "\(n / 3600)h \((n % 3600) / 60)m"
    }

    struct Counts {
        var on = 0.0, unsure = 0.0, off = 0.0
        init(_ segments: [TimelineSegment]) {
            for s in segments { switch s.kind { case .on: on += s.seconds; case .unsure: unsure += s.seconds; case .off: off += s.seconds; case .gap: break } }
        }
    }
}

/// A thin bar that fills from empty each time the notch opens: Droppy's progress bar, 5 pt.
struct ShelfTrack: View {
    var fraction: Double
    @State private var filled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Capsule().fill(Color.white.opacity(0.2)).frame(height: 5).overlay(alignment: .leading) {
            GeometryReader { r in
                Capsule().fill(Color.white.opacity(0.9)).frame(width: fraction <= 0 ? 0 : max(5, r.size.width * (filled || reduceMotion ? fraction : 0)))
            }
        }
        .animation(Motion.out(0.6).delay(0.16), value: filled)
        .animation(Motion.out(0.4), value: fraction)
        .onAppear { filled = true }
        .accessibilityHidden(true)
    }
}

/// Today's time on task against the goal, as Droppy's usage ring: a 3.5 pt arc in the accent around the app's icon.
struct TodayRing: View {
    var fraction: Double
    var arrived: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 3.5)
            Circle().trim(from: 0, to: (arrived || reduceMotion ? fraction : 0)).stroke(NotchView.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round)).rotationEffect(.degrees(-90))
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .animation(Motion.out(0.9).delay(0.3), value: arrived)
        .animation(Motion.out(0.5), value: fraction)
        .accessibilityHidden(true)
    }
}
