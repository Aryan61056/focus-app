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
    @State private var closeHover = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            CueCardHeader(ring: .drift, tint: Tokens.slip, title: c.nudgeTitle) {
                Image(systemName: "sparkle").foregroundStyle(Tokens.accent)
                Text(CueCopy.reminderMeta)
                TimelineView(.everySecond) { _ in Text(BannerView.clock(c.offTopicSecondsNow())).monospacedDigit().foregroundStyle(Tokens.slipInk) }
            }
            .padding(.trailing, Space.l)
            // Two answers, as on the banner. After a long detour another push helps less than a rest, so the break leads.
            HStack(spacing: Space.xs) {
                if c.longDetour {
                    Button(NudgeCopy.breakButton()) { c.takeNudgeBreak() }.buttonStyle(FocusButtonStyle(.primary, small: true))
                    Button("Back to task") { c.act(.backToTask) }.buttonStyle(FocusButtonStyle(.secondary, small: true)).goesTo(c.returnPlace)
                } else {
                    Button("Back to task") { c.act(.backToTask) }.buttonStyle(FocusButtonStyle(.primary, small: true)).goesTo(c.returnPlace)
                    Button("This is part of it") { c.claimOnTask() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                }
            }
            .padding(.leading, 24 + Space.s)
        }
        .floatingCard()
        .overlay(alignment: .topTrailing) { CueClose(hover: $closeHover, help: "Not now") { c.act(.dismiss) }.padding(Space.xs) }
        .accessibilityElement(children: .contain)
    }
}

/// The small round close button on an in-window card, the same as the banner's.
struct CueClose: View {
    @Binding var hover: Bool
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(Tokens.symbol(9, .bold)).foregroundStyle(hover ? Tokens.ink : Tokens.ink2)
                .frame(width: 22, height: 22).background(Circle().fill(hover ? Tokens.controlHover : Tokens.control))
                .frame(width: Tokens.minHit, height: Tokens.minHit).contentShape(Circle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }.animation(Motion.hover, value: hover)
        .help(help).accessibilityLabel(help)
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
            HStack(spacing: Space.xs) {
                Button("Back to task") { c.answerCheckIn(onTask: false) }.buttonStyle(FocusButtonStyle(.primary, small: true)).goesTo(c.returnPlace)
                Button("Yes, this is part of it") { c.answerCheckIn(onTask: true) }.buttonStyle(FocusButtonStyle(.secondary, small: true))
            }
            .padding(.leading, 24 + Space.s)
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
                HStack(spacing: Space.xs) {
                    switch p.kind {
                    case .checkIn:
                        Button("Yes, keep going") { c.rhythmKeepGoing() }.buttonStyle(FocusButtonStyle(.primary, small: true))
                        Button("Take a \(c.rhythmBreakMinutes) minute break") { c.rhythmTakeBreak() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                    case .breakDue(let m):
                        Button("Start the break") { c.rhythmTakeBreak() }.buttonStyle(FocusButtonStyle(.primary, small: true)).accessibilityLabel("Start the \(m) minute break")
                        Button("Five more minutes") { c.rhythmKeepGoing() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                    }
                }
                .padding(.leading, 24 + Space.s)
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
