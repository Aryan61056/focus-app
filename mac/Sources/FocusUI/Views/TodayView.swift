import SwiftUI
import FocusBrain

struct TodayView: View {
    @Bindable var c: SessionController
    @Binding var showStart: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today").font(Tokens.rounded(26, .semibold))
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2)
            }
            if c.isActive { SessionPanel(c: c) } else { IdlePanel(c: c, showStart: $showStart) }
            if let a = c.askResume { AwayBanner(c: c, reason: a) }
            if c.wrapUp && c.isActive { Panel(tinted: true) { Text("Two minutes left. Extend, or wrap up when you are ready.").font(Tokens.text(13.5)) } }
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
                        Text("Focus is watching window titles and text on this Mac.")
                    }
                }
                .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).padding(.top, 12)
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
