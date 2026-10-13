import SwiftUI
import FocusBrain

/// Nudge surfaces. Copy follows PLAN 4.12: calm, second person, never names what you were looking at.
struct NudgeCard: View {
    @Bindable var c: SessionController
    var kind: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(c.nudgeTitle)
                .font(Tokens.rounded(17, .semibold)).fixedSize(horizontal: false, vertical: true)
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
        .padding(20).frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 24).fill(.regularMaterial))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Tokens.line) }
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
    }
}

/// After a warning went unanswered: a plain question. "Yes" teaches Focus the window belongs to the task and ends the climb.
struct CheckInCard: View {
    @Bindable var c: SessionController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NudgeCopy.checkInTitle(task: c.taskName)).font(Tokens.rounded(17, .semibold)).fixedSize(horizontal: false, vertical: true)
            Text("Focus read the window again and it still does not look like the task.").font(Tokens.text(13)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            Button("Back to task") { c.answerCheckIn(onTask: false) }.buttonStyle(FocusButtonStyle(.primary, expand: true))
            Button("Yes, this is part of it") { c.answerCheckIn(onTask: true) }.buttonStyle(FocusButtonStyle(.secondary, expand: true))
        }
        .padding(20).frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 24).fill(.regularMaterial))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Tokens.line) }
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
    }
}

/// A scheduled prompt: a check-in at your interval, or a break after a block of work. Always answerable in one click.
struct RhythmCard: View {
    @Bindable var c: SessionController
    var body: some View {
        if let p = c.rhythmPrompt {
            VStack(alignment: .leading, spacing: 12) {
                Text(CueCopy.rhythmTitle(p.kind, task: c.taskName)).font(Tokens.rounded(17, .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(CueCopy.rhythmBody(p.kind)).font(Tokens.text(13)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                switch p.kind {
                case .checkIn:
                    Button("Yes, keep going") { c.rhythmKeepGoing() }.buttonStyle(FocusButtonStyle(.primary, expand: true))
                    Button("Take a \(c.rhythmBreakMinutes) minute break") { c.rhythmTakeBreak() }.buttonStyle(FocusButtonStyle(.secondary, expand: true))
                case .breakDue(let m):
                    Button("Start a \(m) minute break") { c.rhythmTakeBreak() }.buttonStyle(FocusButtonStyle(.primary, expand: true))
                    Button("Five more minutes") { c.rhythmKeepGoing() }.buttonStyle(FocusButtonStyle(.secondary, expand: true))
                }
            }
            .padding(20).frame(width: 340)
            .background(RoundedRectangle(cornerRadius: 24).fill(.regularMaterial))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Tokens.line) }
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
            .accessibilityElement(children: .contain)
        }
    }
}

struct ReentryCard: View {
    @Bindable var c: SessionController
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What is the next step?").font(Tokens.rounded(15, .semibold))
            TextField("One small thing", text: $text).textFieldStyle(.plain).onSubmit { if !text.isEmpty { c.saveNextStep(text) } }.padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: Tokens.radiusControl).fill(Tokens.control))
            HStack { Spacer(); Button("Skip") { c.manualNextStep = false; c.act(.nextStep) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                Button("Save") { c.saveNextStep(text) }.buttonStyle(FocusButtonStyle(.primary, small: true)).disabled(text.isEmpty) }
        }
        .padding(18).frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 20).fill(.regularMaterial))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Tokens.line) }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}
