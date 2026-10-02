import SwiftUI
import FocusBrain

struct TodayView: View {
    @Bindable var c: SessionController
    @Binding var showStart: Bool

    var body: some View {
        Scroller { content }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today").font(Tokens.rounded(26, .semibold))
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2)
            }
            if c.isActive { SessionPanel(c: c); ReadingPanel(c: c) } else if !c.prefs.introSeen && c.summary == nil && (c.store?.sessions.isEmpty ?? true) { IntroPanel(c: c, showStart: $showStart) } else { IdlePanel(c: c, showStart: $showStart); HowFocusDecides() }
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
            }
            if let a = c.askResume { AwayBanner(c: c, reason: a) }
            if c.wrapUp && c.isActive { Panel(tinted: true) { Text("Two minutes left. Extend, or wrap up when you are ready.").font(Tokens.text(13.5)) } }
            if let st = c.store { TodayExtras(c: c, store: st) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct SessionPanel: View {
    @Bindable var c: SessionController
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 18) {
                    RingView(c.ringState, color: c.ringColor).frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.taskName).font(Tokens.rounded(20, .semibold)).lineLimit(2)
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text("\(c.mode == .timed ? "Timed" : "Open") session, \(c.clockText())\(c.mode == .timed ? " left" : "")")
                                .font(Tokens.text(13)).foregroundStyle(Tokens.ink2).monospacedDigit()
                        }
                        StateChip(label: c.presenceLabel, ring: c.ringState, on: c.ringColor == Tokens.accent)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        if c.isPaused { Button("Resume") { c.act(.resume) }.buttonStyle(FocusButtonStyle(.secondary)) }
                        else { Button("Pause") { c.act(.pause) }.buttonStyle(FocusButtonStyle(.secondary)) }
                        Menu("Take a break") {
                            ForEach([5, 10, 15], id: \.self) { m in Button("\(m) minutes") { c.act(.breakTime, minutes: m) } }
                        }.menuStyle(.button).buttonStyle(FocusButtonStyle(.secondary)).fixedSize()
                        Button("End session") { c.end() }.buttonStyle(FocusButtonStyle(.plain))
                    }
                }
                Divider().overlay(Tokens.line).padding(.top, 14)
                HStack(spacing: 8) {
                    if c.shadow {
                        Image(systemName: "eye").foregroundStyle(Tokens.ink2)
                        Text(c.shadowMarks == 0 ? "Practice mode: Focus is watching but will not interrupt you."
                             : "Practice mode: \(c.shadowMarks) moment\(c.shadowMarks == 1 ? "" : "s") to review later.")
                    } else {
                        Text(c.prefs.readScreen ? "Focus reads app names, window titles and the words on screen, on this Mac." : "Focus reads app names and window titles on this Mac.")
                    }
                }
                .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).padding(.top, 12)
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
                Text("Tell Focus what you are working on. It compares the window in front with that task, on this Mac, and nudges gently when you drift. When it is not sure, it does nothing.")
                    .font(Tokens.text(14.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 520, alignment: .leading)
                Text("Your first sessions are practice: Focus watches and learns, and does not interrupt.").font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2)
                HStack(spacing: 10) {
                    Button("Start a session") { c.prefs.introSeen = true; showStart = true }.buttonStyle(FocusButtonStyle(.primary)).keyboardShortcut("n")
                    Button("Skip intro") { c.prefs.introSeen = true }.buttonStyle(FocusButtonStyle(.plain))
                }
            }
        }
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
                    Text("Tell Focus what you are working on and it will keep an eye out for drift.").font(Tokens.text(14)).foregroundStyle(Tokens.ink2)
                }
                Button("Start session") { showStart = true }.buttonStyle(FocusButtonStyle(.primary)).keyboardShortcut("n")
                if c.summary != nil, c.askLoudness {
                    Divider().overlay(Tokens.line).padding(.vertical, 4)
                    Text("How was that?").font(Tokens.text(14, .semibold))
                    Text("Focus spoke up during this session. This sets how readily it does.").font(Tokens.text(13)).foregroundStyle(Tokens.ink2)
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
