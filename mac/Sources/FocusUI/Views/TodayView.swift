import SwiftUI
import FocusBrain

struct TodayView: View {
    @Bindable var c: SessionController
    @Binding var showStart: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Scroller { content }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            HeroBanner(caption: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))) { NotchPreviewPill(c: c) }
            // The AI's reading stays the hero while a session runs; progress follows it. Between sessions it sits right under the status.
            if c.isActive {
                SessionPanel(c: c); ReadingPanel(c: c); progress; if c.aiAvailable { AskPanel(c: c) }
            } else if !c.prefs.introSeen && c.summary == nil && (c.store?.sessions.isEmpty ?? true) {
                IntroPanel(c: c, showStart: $showStart)
            } else {
                IdlePanel(c: c, showStart: $showStart); progress
                if c.aiAvailable && c.stats.total > 0 { AskPanel(c: c) }
                HowFocusDecides()
            }
            if case .unavailable(let why) = c.judgeStatus {
                Panel(tinted: true) {
                    HStack(spacing: 14) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(Tokens.ink2)
                        Text("\(why) Until then Focus cannot judge windows, so it will not nudge you.")
                            .font(Tokens.text(13.5)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Button("Open settings") { c.onOpenModelSettings?() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                    }
                }
                .transition(.rise(reduce: reduceMotion))
            }
            if c.showContextTip {
                Panel(tinted: true) {
                    HStack(spacing: 14) {
                        Image(systemName: "lightbulb").foregroundStyle(Tokens.ink2)
                        Text("Focus is often not sure about this project. A line about what counts, under Projects, can help. It still prefers to do nothing when a window is unclear.")
                            .font(Tokens.text(13.5)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Button("Describe project") { c.prefs.contextTipDismissed = true; c.requestSection(.projects) }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                        Button("Dismiss") { c.prefs.contextTipDismissed = true }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                }
                .transition(.rise(reduce: reduceMotion))
            }
            if c.windowAccess == .appNamesOnly {
                Panel(tinted: true) {
                    HStack(spacing: 14) {
                        Image(systemName: "lock.open").foregroundStyle(Tokens.ink2)
                        Text(c.isActive ? "Focus can only see which app is in front. Allow Accessibility and it can read window titles too, which it needs to tell work from drift. If Focus is already switched on in that list, remove it with the minus button and add it again." : "To tell work from drift, Focus needs Accessibility so it can read window titles during a session. You can do this now or later. If Focus is already switched on in that list, remove it with the minus button and add it again.")
                            .font(Tokens.text(13.5)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Button("Open Accessibility settings") { c.onOpenAccessSettings?() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                    }
                }
                .transition(.rise(reduce: reduceMotion))
            }
            if let u = c.visibleUpdate {
                Panel(tinted: true) {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Tokens.ink2)
                        Text("A newer build of Focus is ready on this Mac. Restarting takes a few seconds.").font(Tokens.text(13.5)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Button("Restart to update") { c.installUpdate() }.buttonStyle(FocusButtonStyle(.primary, small: true)).help("Build \(u.buildID)")
                        Button("Later") { c.dismissUpdate() }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                }
                .transition(.rise(reduce: reduceMotion))
            }
            if let a = c.askResume { AwayBanner(c: c, reason: a).transition(.rise(reduce: reduceMotion)) }
            if c.wrapUp && c.isActive { Panel(tinted: true) { Text("Two minutes left. Extend, or wrap up when you are ready.").font(Tokens.text(13.5)) }.transition(.rise(reduce: reduceMotion)) }
            if let st = c.store { TodayExtras(c: c, store: st) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension TodayView {
    @ViewBuilder var progress: some View {
        if let st = c.store, !st.sessions.isEmpty { ProgressPanel(c: c, store: st) }
    }
}

struct SessionPanel: View {
    @Bindable var c: SessionController
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 18) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        LiveRing(c.ringState, color: c.ringColor).frame(width: 72, height: 72)
                            .background { RingGlow(on: c.ringColor == Tokens.accent && !c.isPaused, color: Tokens.accent).padding(-6) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.taskName).font(Tokens.rounded(17, .semibold)).foregroundStyle(Tokens.ink2).lineLimit(1)
                        // The number you glance at is the biggest thing on the screen.
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let t = c.clockText()
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(t).font(Tokens.rounded(38, .semibold)).monospacedDigit().tracking(-0.5)
                                    .contentTransition(.numericText(countsDown: c.mode == .timed)).motion(Motion.out(0.3), value: t)
                                if c.mode == .timed { Text("left").font(Tokens.text(14, .medium)).foregroundStyle(Tokens.ink2) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        HStack(spacing: 8) {
                            StateChip(label: c.presenceLabel, ring: c.ringState, on: c.ringColor == Tokens.accent)
                            if let m = c.moment { MomentLine(moment: m) }
                        }
                        .motion(Motion.notchSettle, value: c.moment)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        // One button that changes its word, so the pointer that just paused is already on Resume.
                        Button { c.act(c.isPaused ? .resume : .pause) } label: {
                            Label(c.isPaused ? "Resume" : "Pause", systemImage: c.isPaused ? "play.fill" : "pause.fill")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(FocusButtonStyle(.secondary))
                        .motion(Motion.out(0.2), value: c.isPaused)
                        Menu("Take a break") {
                            ForEach([5, 10, 15], id: \.self) { m in Button("\(m) minutes") { c.act(.breakTime, minutes: m) } }
                        }.menuStyle(.button).buttonStyle(FocusButtonStyle(.secondary)).fixedSize()
                        Button("End session") { c.end() }.buttonStyle(FocusButtonStyle(.plain))
                    }
                }
                Divider().overlay(Tokens.line).padding(.top, 14)
                // Always a visible sign of what Focus is doing (principle 5), in a few words.
                HStack(spacing: 7) {
                    if c.isPaused {
                        Image(systemName: "pause.circle")
                        Text("Paused. No nudges until you resume.")
                    } else if c.shadow {
                        Image(systemName: "eye")
                        Text(c.shadowMarks == 0 ? "Practice: watching, no nudges" : "Practice: \(c.shadowMarks) moment\(c.shadowMarks == 1 ? "" : "s") to review")
                    } else {
                        Image(systemName: "eye")
                        Text(c.prefs.readScreen ? "Reading window titles and on-screen words, on this Mac" : "Reading window titles, on this Mac")
                    }
                }
                .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).padding(.top, 12)
                .contentTransition(.opacity)
                .motion(Motion.out(0.24), value: c.isPaused)
            }
        }
    }
}

/// First run: one short screen, one main action (calm rules 1 and 3). Nothing is asked before the first session.
struct IntroPanel: View {
    @Bindable var c: SessionController
    @Binding var showStart: Bool
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Stay on what you meant to do").font(Tokens.rounded(24, .semibold))
                Text("Say what you are working on. Focus nudges you, gently, when you drift. When it is not sure, it stays quiet.")
                    .font(Tokens.text(14.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 520, alignment: .leading)
                if !c.prefs.practiceRemoved { Text("Your first sessions are practice: it watches, it does not interrupt.").font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 520, alignment: .leading) }
                HStack(spacing: 10) {
                    Button("Start a session") { c.prefs.introSeen = true; showStart = true }.buttonStyle(FocusButtonStyle(.primary)).keyboardShortcut("n")
                    Button("Skip intro") { c.prefs.introSeen = true }.buttonStyle(FocusButtonStyle(.plain))
                }
            }
        }
    }
}

/// After a session: where to pick up next time. Saved on the project, offered on the start sheet. Optional.
struct PickUpNote: View {
    @Bindable var c: SessionController
    var project: Project
    @State private var text = ""
    @State private var loaded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Where to pick up next time").font(Tokens.text(13, .semibold))
            TextField("One small thing", text: $text).textFieldStyle(.plain).padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: Tokens.radiusControl).fill(Tokens.control))
                .onSubmit { c.setProjectNextStep(text) }
                .onChange(of: text) { _, v in if loaded { c.setProjectNextStep(v) } }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .onAppear { text = project.nextStep; loaded = true }
    }
}

struct IdlePanel: View {
    @Bindable var c: SessionController
    @Binding var showStart: Bool
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                if let s = c.summary {
                    Text("Session finished").font(Tokens.rounded(20, .semibold))
                    Text(sentence(s)).font(Tokens.text(14)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No session running").font(Tokens.rounded(20, .semibold))
                    Text("Say what you are working on. Focus keeps watch.").font(Tokens.text(14)).foregroundStyle(Tokens.ink2)
                }
                if c.summary != nil, let h = c.highlight { HighlightLine(highlight: h) }
                if c.summary != nil { RecapBlock(c: c) }
                if c.summary != nil, let p = c.projectForNote { PickUpNote(c: c, project: p) }
                Button("Start session") { showStart = true }.buttonStyle(FocusButtonStyle(.primary)).keyboardShortcut("n")
                if c.summary != nil, c.askLoudness {
                    Divider().overlay(Tokens.line).padding(.vertical, 4)
                    Text("How was that?").font(Tokens.text(14, .semibold))
                    Text("Sets how readily Focus speaks up.").font(Tokens.text(13)).foregroundStyle(Tokens.ink2)
                    HStack(spacing: 8) {
                        Button("Too quiet") { c.prefs.answerLoudness(.tooQuiet) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                        Button("About right") { c.prefs.answerLoudness(.aboutRight) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                        Button("Too loud") { c.prefs.answerLoudness(.tooLoud) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                }
            }
        }
    }

    func sentence(_ s: SessionSummary) -> String {
        let on = Int(((s.activeSeconds - s.offTopicSeconds - s.unsureSeconds) / 60).rounded())
        let slips = s.drifts == 0 ? "No slips." : (s.drifts == 1 ? "One slip." : "\(s.drifts) slips.")
        return "\(max(on, 0)) minutes on task. \(slips)"
    }
}

struct AwayBanner: View {
    @Bindable var c: SessionController
    var reason: String
    var body: some View {
        Panel(tinted: true) {
            HStack {
                Text(reason == "meeting" ? "Your meeting looks over. Pick up where you left off?" : "Welcome back. Pick up where you left off?").font(Tokens.text(13.5))
                Spacer()
                Button("Resume") { c.act(.resume) }.buttonStyle(FocusButtonStyle(.primary, small: true))
                Button("End session") { c.end() }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        }
    }
}
