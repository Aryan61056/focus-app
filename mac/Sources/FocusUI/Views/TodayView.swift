import SwiftUI
import FocusBrain

/// Today. Two jobs, and the screen does one of them at a time.
/// Between sessions: say what you are working on and press Return, with your day and week under it.
/// During a session, for a three second glance: Focus's bar, its call, the session as one band (TodayLiveMain).
/// The Focus panel beside it (TodayPanel) holds what Focus did, Ask Focus and the goal. At most one notice shows at a time.
struct TodayView: View {
    @Bindable var c: SessionController
    @Binding var showStart: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PanelLayout {
            content.padding(.horizontal, Space.xl).padding(.top, Space.l).padding(.bottom, Space.xl).frame(maxWidth: 960, alignment: .leading)
        } side: {
            TodayPanel(c: c)
        }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if let n = notice { NoticeRow(notice: n, c: c).transition(.rise(reduce: reduceMotion)) }
            if c.isActive {
                // A break shows the thoughts you parked; "I'm stuck" swaps the call for a few small next actions.
                if c.presence.reason == "break", let store = c.store, !store.thoughts.isEmpty { ParkingLotCard(store: store) }
                else if c.stuckShown { StuckCard(c: c).transition(.opacity) }
                else { TodayLiveMain(c: c, onStuck: { c.requestNextActions() }) }
            } else {
                DashHeader(c: c)
                if c.summary != nil { JustFinishedCard(c: c) }
                if let store = c.store, !store.thoughts.isEmpty { ParkingLotCard(store: store) }
                StartCard(c: c, showStart: $showStart, intro: firstRun)
                if firstRun { HowItWorks(c: c).fixedSize(horizontal: false, vertical: true) }
                if let st = c.store, !st.sessions.isEmpty { DaySection(store: st); WeekSection(store: st) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var firstRun: Bool { !c.prefs.introSeen && c.summary == nil && (c.store?.sessions.isEmpty ?? true) }

    /// The most pressing thing to know, if any. Only one is ever shown; the rest wait until it is dealt with.
    var notice: Notice? {
        if c.saveFailed { return .saveFailed }
        if let a = c.askResume { return .resume(a) }
        if c.wrapUp && c.isActive { return .wrapUp }
        if case .unavailable(let why) = c.judgeStatus { return .modelOff(why) }
        if c.windowAccess == .appNamesOnly { return .access }
        if let u = c.visibleUpdate { return .update(u.buildID) }
        if c.showContextTip { return .contextTip }
        return nil
    }
}

enum Notice {
    case saveFailed, resume(String), wrapUp, modelOff(String), access, update(String), contextTip
}

struct NoticeRow: View {
    var notice: Notice
    @Bindable var c: SessionController

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol).foregroundStyle(Tokens.ink2).frame(width: 18)
            Text(text).font(Tokens.text(.body)).fixedSize(horizontal: false, vertical: true).help(help)
            Spacer(minLength: 12)
            buttons
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .modifier(CardSurface())
        .accessibilityElement(children: .contain)
    }

    var symbol: String {
        switch notice {
        case .saveFailed: return "externaldrive.badge.exclamationmark"
        case .resume: return "play.circle"; case .wrapUp: return "hourglass"; case .modelOff: return "exclamationmark.circle"
        case .access: return "lock.open"; case .update: return "arrow.triangle.2.circlepath"; case .contextTip: return "lightbulb"
        }
    }
    var text: String {
        switch notice {
        case .saveFailed: return "Focus could not save your data on this Mac, so new sessions may be lost. Check that the disk has room."
        case .resume(let r): return r == "meeting" ? "Your meeting looks over. Pick up where you left off?" : "Welcome back. Pick up where you left off?"
        case .wrapUp: return c.sessionDeadline == nil ? "Two minutes left. Extend, or wrap up when you are ready." : "Two minutes left. Wrap up when you are ready."
        case .modelOff(let why): return "\(why) Until then Focus will not nudge you."
        case .access: return "Allow Accessibility so Focus can read window titles."
        case .update: return "A newer build is ready. Restarting takes a few seconds."
        case .contextTip: return "Focus is often unsure about this project. A line about what counts helps."
        }
    }
    var help: String {
        switch notice {
        case .access: return "Focus needs Accessibility to tell work from drift. If Focus is already switched on in that list, remove it with the minus button and add it again."
        case .contextTip: return "Under Projects. Focus still prefers to do nothing when a window is unclear."
        case .modelOff: return "Without the on-device model Focus cannot judge windows, so it does nothing."
        default: return text
        }
    }
    @ViewBuilder var buttons: some View {
        switch notice {
        case .saveFailed: Button("Try again") { c.store?.retrySave() }.buttonStyle(FocusButtonStyle(.primary, small: true))
        case .resume:
            Button("Resume") { c.act(.resume) }.buttonStyle(FocusButtonStyle(.primary, small: true))
            Button("End session") { c.end() }.buttonStyle(FocusButtonStyle(.plain, small: true))
        case .wrapUp: EmptyView()
        case .modelOff: Button("Open settings") { c.onOpenModelSettings?() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
        case .access: Button("Open settings") { c.onOpenAccessSettings?() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
        case .update(let build):
            Button("Restart to update") { c.installUpdate() }.buttonStyle(FocusButtonStyle(.primary, small: true)).help("Build \(build)")
            Button("Later") { c.dismissUpdate() }.buttonStyle(FocusButtonStyle(.plain, small: true))
        case .contextTip:
            Button("Describe project") { c.prefs.contextTipDismissed = true; c.requestSection(.projects) }.buttonStyle(FocusButtonStyle(.secondary, small: true))
            Button("Dismiss") { c.prefs.contextTipDismissed = true }.buttonStyle(FocusButtonStyle(.plain, small: true))
        }
    }
}

/// Between sessions: a greeting and one quiet line about the day.
struct DashHeader: View {
    @Bindable var c: SessionController
    var body: some View {
        let now = c.date()
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(Self.greeting(hour: Calendar.current.component(.hour, from: now))).font(Tokens.rounded(.title2, .semibold)).accessibilityAddTraits(.isHeader)
            Text(subtitle(now)).font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2)
        }
    }
    func subtitle(_ now: Date) -> String {
        let day = now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard let st = c.store else { return day }
        let total = DayStats.total(st.sessions, on: now)
        return total.sessions == 0 ? day : "\(day) \u{00B7} \(durationText(total.onTaskSeconds)) on task so far"
    }
    static func greeting(hour: Int) -> String {
        switch hour { case 5..<12: return "Good morning"; case 12..<17: return "Good afternoon"; case 17..<22: return "Good evening"; default: return "Working late" }
    }
}
