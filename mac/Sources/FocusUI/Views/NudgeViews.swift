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
                Button("That was fine") { c.act(.thatWasFine) }.buttonStyle(FocusButtonStyle(.plain, small: true))
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

/// Strict preset: a pause screen over the window, one primary action, two ways out.
struct GateOverlay: View {
    @Bindable var c: SessionController
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 14) {
                RingView(.drift, color: Tokens.ink).frame(width: 44, height: 44)
                Text("Take a moment").font(Tokens.rounded(22, .semibold))
                Text(NudgeCopy.gateBody(tone: c.prefs.nudgeTone, task: c.taskName, longDetour: c.longDetour)).font(Tokens.text(14)).foregroundStyle(Tokens.ink2)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if c.longDetour {
                    Button(NudgeCopy.breakButton()) { c.takeNudgeBreak() }.buttonStyle(FocusButtonStyle(.primary, expand: true)).frame(width: 240)
                    Button("Back to task") { c.act(.backToTask) }.buttonStyle(FocusButtonStyle(.secondary, expand: true)).frame(width: 240)
                } else {
                    Button("Back to task") { c.act(.backToTask) }.buttonStyle(FocusButtonStyle(.primary, expand: true)).frame(width: 240)
                }
                HStack {
                    Button("That was fine") { c.act(.thatWasFine) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    Button("Snooze 15 min") { c.act(.snooze, minutes: 15) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                }
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 28).fill(Tokens.window))
            .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(Tokens.line) }
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
