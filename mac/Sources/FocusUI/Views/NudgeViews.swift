import SwiftUI
import FocusBrain

/// Nudge surfaces. Copy follows PLAN 4.12: calm, second person, never names what you were looking at.
struct NudgeCard: View {
    @Bindable var c: SessionController
    var kind: String
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(c.nudgeTitle)
                .font(Tokens.rounded(.headline, .semibold)).fixedSize(horizontal: false, vertical: true)
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

/// After a warning went unanswered: a plain question. "Yes" teaches Focus the window belongs to the task and ends the climb.
struct CheckInCard: View {
    @Bindable var c: SessionController
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(NudgeCopy.checkInTitle(task: c.taskName)).font(Tokens.rounded(.headline, .semibold)).fixedSize(horizontal: false, vertical: true)
            Text("Focus read the window again and it still does not look like the task.").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
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
            VStack(alignment: .leading, spacing: Space.s) {
                Text(CueCopy.rhythmTitle(p.kind, task: c.taskName)).font(Tokens.rounded(.headline, .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(CueCopy.rhythmBody(p.kind)).font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                switch p.kind {
                case .checkIn:
                    Button("Yes, keep going") { c.rhythmKeepGoing() }.buttonStyle(FocusButtonStyle(.primary, expand: true))
                    Button("Take a \(c.rhythmBreakMinutes) minute break") { c.rhythmTakeBreak() }.buttonStyle(FocusButtonStyle(.secondary, expand: true))
                case .breakDue(let m):
                    Button("Start a \(m) minute break") { c.rhythmTakeBreak() }.buttonStyle(FocusButtonStyle(.primary, expand: true))
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
            Text("What is the next step?").font(Tokens.rounded(.callout, .semibold))
            TextField("One small thing", text: $text).font(Tokens.text(.body)).onSubmit { if !text.isEmpty { c.saveNextStep(text) } }.wellField()
            HStack { Spacer(); Button("Skip") { c.manualNextStep = false; c.act(.nextStep) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                Button("Save") { c.saveNextStep(text) }.buttonStyle(FocusButtonStyle(.primary, small: true)).disabled(text.isEmpty) }
        }
        .floatingCard()
    }
}
