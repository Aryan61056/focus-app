import SwiftUI
import FocusBrain

/// Nudge surfaces inside the Focus window. The banner over the window you are in carries the same moments wherever you are, so these show
/// only when the banner is switched off or not up (RootView). Same parts as the banner: the state ring, the words, one line of what Focus
/// saw, and at most three answers. Copy follows PLAN 4.12: calm, second person, never names what you were looking at.
struct CueCardHeader<Meta: View>: View {
    var ring: RingState
    var tint: Color
    var title: String
    @ViewBuilder var meta: Meta
    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            RingView(ring, color: tint).frame(width: 24, height: 24).padding(.top, 1)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).font(Tokens.text(.headline, .semibold)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) { meta }.font(Tokens.text(.caption, .medium)).foregroundStyle(Tokens.ink2)
            }
        }
    }
}

struct NudgeCard: View {
    @Bindable var c: SessionController
    var kind: String
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            CueCardHeader(ring: .drift, tint: Tokens.slip, title: c.nudgeTitle) {
                Image(systemName: "sparkle").foregroundStyle(Tokens.accent)
                Text(CueCopy.reminderMeta)
                TimelineView(.everySecond) { _ in Text(BannerView.clock(c.offTopicSecondsNow())).monospacedDigit().foregroundStyle(Tokens.slipInk) }
            }
            if c.longDetour {
                // After a long detour another push helps less than a rest; the break leads and going back stays one click away.
                Button(NudgeCopy.breakButton()) { c.takeNudgeBreak() }.buttonStyle(FocusButtonStyle(.primary, expand: true))
                Button("Back to task") { c.act(.backToTask) }.buttonStyle(FocusButtonStyle(.secondary, expand: true))
            } else {
                Button("Back to task") { c.act(.backToTask) }.buttonStyle(FocusButtonStyle(.primary, expand: true))
            }
            HStack {
                Button("That was fine") { c.claimOnTask() }.buttonStyle(FocusButtonStyle(.plain, small: true))
                Spacer()
                Button("Not now") { c.act(.dismiss) }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        }
        .floatingCard()
        .accessibilityElement(children: .contain)
    }
}

/// After a warning went unanswered: a plain question. "Yes" asks you to explain a window Focus read as off topic; "Back to task" sends you back.
struct CheckInCard: View {
    @Bindable var c: SessionController
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            CueCardHeader(ring: .drift, tint: Tokens.slip, title: NudgeCopy.checkInTitle(task: c.taskName)) {
                Image(systemName: "sparkle").foregroundStyle(Tokens.accent)
                Text(CueCopy.checkInMeta)
            }
            Button("Back to task") { c.answerCheckIn(onTask: false) }.buttonStyle(FocusButtonStyle(.primary, expand: true))
            Button("Yes, this is part of it") { c.answerCheckIn(onTask: true) }.buttonStyle(FocusButtonStyle(.secondary, expand: true))
        }
        .floatingCard()
        .accessibilityElement(children: .contain)
    }
}

/// A scheduled prompt: a check-in at your interval, or a break after a block of work. Always answerable in one click.
struct RhythmCard: View {
    @Bindable var c: SessionController
    var body: some View {
        if let p = c.rhythmPrompt {
            VStack(alignment: .leading, spacing: Space.m) {
                CueCardHeader(ring: p.kind.ring, tint: Tokens.accent, title: CueCopy.rhythmTitle(p.kind, task: c.taskName)) {
                    Image(systemName: "clock")
                    Text(CueCopy.rhythmMeta(p.kind, checkInMinutes: c.prefs.checkInMinutes))
                }
                switch p.kind {
                case .checkIn:
                    Button("Yes, keep going") { c.rhythmKeepGoing() }.buttonStyle(FocusButtonStyle(.primary, expand: true))
                    Button("Take a \(c.rhythmBreakMinutes) minute break") { c.rhythmTakeBreak() }.buttonStyle(FocusButtonStyle(.secondary, expand: true))
                case .breakDue(let m):
                    Button("Start the break") { c.rhythmTakeBreak() }.buttonStyle(FocusButtonStyle(.primary, expand: true)).accessibilityLabel("Start the \(m) minute break")
                    Button("Five more minutes") { c.rhythmKeepGoing() }.buttonStyle(FocusButtonStyle(.secondary, expand: true))
                }
            }
            .floatingCard()
            .accessibilityElement(children: .contain)
        }
    }
}

struct ReentryCard: View {
    @Bindable var c: SessionController
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("What is the next step?").font(Tokens.text(.headline, .semibold))
            TextField("One small thing", text: $text).font(Tokens.text(.body)).onSubmit { if !text.isEmpty { c.saveNextStep(text) } }.wellField()
            HStack { Spacer(); Button("Skip") { c.manualNextStep = false; c.act(.nextStep) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                Button("Save") { c.saveNextStep(text) }.buttonStyle(FocusButtonStyle(.primary, small: true)).disabled(text.isEmpty) }
        }
        .floatingCard()
    }
}
