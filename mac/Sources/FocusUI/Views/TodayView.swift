import SwiftUI
import FocusBrain

/// Today. Two jobs, and the screen does one of them at a time.
/// Between sessions: say what you are working on and press Return (one field, your projects one tap away, how the day is going).
/// During a session, for a three second glance: how you are doing, what Focus is reading and why, and nothing that needs reading twice.
/// At most one notice shows at a time, so a screen never opens with a stack of banners.
struct TodayView: View {
    @Bindable var c: SessionController
    @Binding var showStart: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 900

    var body: some View {
        Scroller { content }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// Side by side when there is room; stacked when the window is narrow.
    var wide: Bool { width >= 820 }

    var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Droppy heads its pages with a picture: here a live copy of the notch over the app's artwork.
            HeroBanner(caption: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))) { NotchPreviewPill(c: c) }
            if c.isActive { LiveHeader(c: c) } else { DashHeader(c: c) }
            if let n = notice { NoticeRow(notice: n, c: c) }
            if !hasSide {
                VStack(alignment: .leading, spacing: 18) { main; if !firstRun { HowDecidesButton() } }
            } else if wide {
                HStack(alignment: .top, spacing: 28) {
                    main.frame(maxWidth: .infinity, alignment: .topLeading)
                    side.frame(width: 284, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 26) { main; side }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Nothing to put beside the start card on a first day, so it gets the whole width and the page stays quiet.
    var hasSide: Bool { c.isActive || !(c.store?.sessions.isEmpty ?? true) }

    var firstRun: Bool { !c.prefs.introSeen && c.summary == nil && (c.store?.sessions.isEmpty ?? true) }

    @ViewBuilder var main: some View {
        VStack(alignment: .leading, spacing: 26) {
            if c.isActive {
                SeeingCard(c: c)
                if c.aiAvailable { AskPanel(c: c) }
            } else {
                if c.summary != nil { JustFinishedCard(c: c) }
                StartCard(c: c, showStart: $showStart, intro: firstRun)
                if firstRun { HowItWorks(c: c).fixedSize(horizontal: false, vertical: true) }
                if let st = c.store { DaySection(store: st); WeekSection(store: st) }
            }
        }
    }

    @ViewBuilder var side: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let st = c.store { GoalCluster(c: c, store: st) }
            if c.isActive { SessionTally(stats: c.stats) }
            HowDecidesButton()
        }
    }

    /// The most pressing thing to know, if any. Only one is ever shown; the rest wait until it is dealt with.
    var notice: Notice? {
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
    case resume(String), wrapUp, modelOff(String), access, update(String), contextTip
}

struct NoticeRow: View {
    var notice: Notice
    @Bindable var c: SessionController

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Tokens.ink2).frame(width: 18)
            Text(text).font(Tokens.text(13.5)).fixedSize(horizontal: false, vertical: true).help(help)
            Spacer(minLength: 12)
            buttons
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .modifier(CardSurface(radius: 14))
        .accessibilityElement(children: .contain)
    }

    var symbol: String {
        switch notice {
        case .resume: return "play.circle"; case .wrapUp: return "hourglass"; case .modelOff: return "exclamationmark.circle"
        case .access: return "lock.open"; case .update: return "arrow.triangle.2.circlepath"; case .contextTip: return "lightbulb"
        }
    }
    var text: String {
        switch notice {
        case .resume(let r): return r == "meeting" ? "Your meeting looks over. Pick up where you left off?" : "Welcome back. Pick up where you left off?"
        case .wrapUp: return "Two minutes left. Extend, or wrap up when you are ready."
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
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.greeting(hour: Calendar.current.component(.hour, from: now))).font(Tokens.rounded(28, .semibold)).accessibilityAddTraits(.isHeader)
            Text(subtitle(now)).font(Tokens.text(14)).foregroundStyle(Tokens.ink2)
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

/// During a session: the ring, the task, the clock and the controls, in one row you can read from across the desk.
struct LiveHeader: View {
    @Bindable var c: SessionController
    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            // The live ring: its arc sweeps with the clock, a change of state blurs in, and it breathes while you are on task.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                LiveRing(c.ringState, color: c.ringColor).frame(width: 76, height: 76)
                    .background { RingGlow(on: c.ringColor == Tokens.accent && !c.isPaused, color: Tokens.accent).padding(-6) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(c.taskName).font(Tokens.rounded(28, .semibold)).lineLimit(2)
                HStack(spacing: 8) {
                    StateChip(label: c.presenceLabel, ring: c.ringState, on: c.ringColor == Tokens.accent)
                    if let m = c.moment { MomentLine(moment: m) }
                    if let note = statusNote { Text(note).font(Tokens.text(13)).foregroundStyle(Tokens.ink2).lineLimit(1) }
                }
                .motion(Motion.notchSettle, value: c.moment)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let t = c.clockText()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(t).font(Tokens.rounded(34, .semibold)).monospacedDigit()
                            .contentTransition(.numericText(countsDown: c.mode == .timed)).motion(Motion.out(0.3), value: t)
                        Text(c.mode == .timed ? "left" : "elapsed").font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
                    }
                }
                HStack(spacing: 8) {
                    // One button that changes its word, so the pointer that just paused is already on Resume.
                    Button { c.act(c.isPaused ? .resume : .pause) } label: {
                        Label(c.isPaused ? "Resume" : "Pause", systemImage: c.isPaused ? "play.fill" : "pause.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(FocusButtonStyle(.secondary))
                    .motion(Motion.out(0.2), value: c.isPaused)
                    Menu("Break") {
                        ForEach([5, 10, 15], id: \.self) { m in Button("\(m) minutes") { c.act(.breakTime, minutes: m) } }
                    }.menuStyle(.button).buttonStyle(FocusButtonStyle(.secondary)).fixedSize()
                    Button("End") { c.end() }.buttonStyle(FocusButtonStyle(.plain))
                }
            }
        }
    }
    var statusNote: String? {
        if c.isPaused { return "No nudges until you resume." }
        if c.shadow { return c.shadowMarks == 0 ? "Practice: watching, not interrupting." : "Practice: \(c.shadowMarks) to review later." }
        return nil
    }
}
