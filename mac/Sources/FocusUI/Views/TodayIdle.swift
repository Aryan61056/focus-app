import SwiftUI
import FocusBrain

// The pieces of Today between sessions.

/// The start surface. One field, Return to begin. With no text, Return continues the last project, so a returning user presses one key.
struct StartCard: View {
    @Bindable var c: SessionController
    @Binding var showStart: Bool
    var intro: Bool
    var body: some View {
        Tile(padding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                StartForm(c: c) {}
                if intro { Button("See how it works") { c.showExample() }.buttonStyle(FocusButtonStyle(.plain, small: true)).help("Try an example with made-up windows") }
            }
        }
    }
    struct Plan: Equatable { var task: String; var projectId: UUID?; var mode: Mode; var duration: Double? }
    static func plan(text: String, timed: Bool, minutes: Int, last: Project?) -> Plan? {
        let p = StartSheet.parse(text)
        if p.task.isEmpty { return last.map { Plan(task: $0.name, projectId: $0.id, mode: .open, duration: nil) } }
        let isTimed = timed || p.minutes != nil
        return Plan(task: p.task, projectId: nil, mode: isTimed ? .timed : .open, duration: isTimed ? Double((p.minutes ?? minutes) * 60) : nil)
    }

}

struct ProjectChip: View {
    @Bindable var c: SessionController
    var project: Project
    var onStart: () -> Void
    @State private var hover = false

    var body: some View {
        let sessions = c.store?.sessions(for: project.id) ?? []
        let detail = project.nextStep.isEmpty ? (sessions.first.map { $0.start.formatted(.relative(presentation: .named)) } ?? "No sessions yet") : "Next: \(project.nextStep)"
        Button { onStart(); _ = c.startWithDraft(task: project.name, projectId: project.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Tokens.onAccent)
                    .frame(width: 24, height: 24).background(Circle().fill(Tokens.accent))
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).font(Tokens.text(13.5, .semibold)).lineLimit(1)
                    Text(detail).font(Tokens.text(12)).foregroundStyle(Tokens.ink2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(maxWidth: 230, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover ? Tokens.controlHover : Tokens.control))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain).onHover { hover = $0 }.disabled(c.isActive)
        .accessibilityLabel("Continue \(project.name)").accessibilityHint(detail)
    }
}

/// After a session: what happened, in one short block. Everything optional sits below it.
struct JustFinishedCard: View {
    @Bindable var c: SessionController
    /// The tick draws itself once when the card arrives: the one moment in a session worth a small flourish.
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if let s = c.summary {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 17, weight: .semibold)).foregroundStyle(Tokens.accent)
                        .modifier(DrawOn(hidden: !drawn && !reduceMotion))
                        .accessibilityHidden(true)
                    Text("Session finished").font(Tokens.rounded(18, .semibold))
                    Spacer()
                }
                .task { try? await Task.sleep(for: .milliseconds(220)); drawn = true }
                Text(sentence(s)).font(Tokens.text(14)).foregroundStyle(Tokens.ink2)
                if let h = c.highlight { HighlightLine(highlight: h) }
                if c.shortSessionOffer {
                    HStack {
                        Button("Keep going") { c.keepGoing() }.buttonStyle(FocusButtonStyle(.primary, small: true))
                        Button("Finish") { c.finishFiveMinutes() }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                } else { SessionGoalResult(c: c) }
                if !c.shortSessionOffer && (c.sessionGoal.isEmpty || c.goalDisposition != nil) { RecapBlock(c: c) }
                if !c.shortSessionOffer && (c.sessionGoal.isEmpty || c.goalDisposition != nil), let p = c.projectForNote { PickUpNote(c: c, project: p) }
                if c.askLoudness && !c.shortSessionOffer && (c.sessionGoal.isEmpty || c.goalDisposition != nil) {
                    Divider().overlay(Tokens.line)
                    HStack(spacing: 8) {
                        Text("Was Focus too loud?").font(Tokens.text(13, .semibold))
                        Spacer()
                        Button("Too quiet") { c.prefs.answerLoudness(.tooQuiet) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                        Button("About right") { c.prefs.answerLoudness(.aboutRight) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                        Button("Too loud") { c.prefs.answerLoudness(.tooLoud) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Light blooms in from the card's empty corner as it arrives, the one moment in a session worth marking. It settles faint.
            .background {
                GeometryReader { g in
                    Halftone(pattern: .bloom(from: UnitPoint(x: 1, y: 0), aspect: g.size.width / max(1, g.size.height)), followsPointer: false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .modifier(CardSurface(radius: 10))
        }
    }
    func sentence(_ s: SessionSummary) -> String {
        let on = Int(((s.activeSeconds - s.offTopicSeconds - s.unsureSeconds) / 60).rounded())
        let slips = s.drifts == 0 ? "No slips." : (s.drifts == 1 ? "One slip." : "\(s.drifts) slips.")
        return "\(max(on, 0)) minutes on task. \(slips)"
    }
}

/// After a session: where to pick up next time. Saved on the project, offered on the start surface. Optional.
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

/// Your day on a clock, with one line under it. Hidden until there is a session to show.
struct DaySection: View {
    @Bindable var store: DataStore
    var body: some View {
        let today = Date.now
        let total = DayStats.total(store.sessions, on: today)
        if total.sessions > 0 {
            let slices = DayStats.slices(store.sessions, on: today)
            Panel { VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle(text: "Your day")
                    Spacer()
                    Text("\(durationText(total.onTaskSeconds)) on task \u{00B7} \(total.sessions) \(total.sessions == 1 ? "session" : "sessions") \u{00B7} \(total.slips == 0 ? "no slips" : (total.slips == 1 ? "1 slip" : "\(total.slips) slips"))")
                        .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
                }
                DayTrack(slices: slices, range: DayStats.axis(for: slices), nowHour: DayStats.hourOfDay(today, .current))
            } }
        }
    }
}

struct WeekSection: View {
    @Bindable var store: DataStore
    var body: some View {
        let week = DayStats.week(store.sessions, endingOn: .now)
        if week.contains(where: { $0.hours > 0 }) {
            let best = week.max { $0.hours < $1.hours }!
            Panel { VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle(text: "This week")
                    Spacer()
                    Text("\(durationText(week.reduce(0) { $0 + $1.hours } * 3600)) on task \u{00B7} longest on \(best.day.formatted(.dateTime.weekday(.wide)))")
                        .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
                }
                WeekBars(days: week)
            } }
        }
    }
}

/// How far into today's goal, as a ring, with the week under it. Click the header to change the goal.
struct GoalCluster: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    @State private var editing = false

    var body: some View {
        if c.prefs.showProgress, c.prefs.dailyGoalMinutes > 0 {
            let goal = Rewards.Goal(seconds: c.todayOnTaskSeconds(), goalSeconds: Double(c.prefs.dailyGoalMinutes) * 60)
            let streak = Rewards.streak(store.sessions, today: .now)
            Tile(padding: 20) {
                VStack(spacing: 18) {
                    HStack {
                        Text("Today's goal").font(Tokens.text(14, .semibold)).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button { editing = true } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(Tokens.ink2).frame(width: 28, height: 28).contentShape(Rectangle()) }
                            .buttonStyle(.plain).help("Change the daily goal").accessibilityLabel("Change the daily goal")
                            .popover(isPresented: $editing, arrowEdge: .bottom) { GoalEditor(prefs: c.prefs) }
                    }
                    GoalRing(goal: goal).frame(width: 148, height: 148)
                    if !store.sessions.isEmpty {
                        VStack(spacing: 10) {
                            WeekStrip(week: streak.week)
                            Text(streak.current == 0 ? "Ready when you are" : (streak.current == 1 ? "1 focus day" : "\(streak.current) focus days in a row"))
                                .font(Tokens.text(13, .semibold))
                                .help(streak.current == 0 ? "A focus day is \(Int(Rewards.focusDaySeconds / 60)) minutes on task." : "Rest days keep it going: \(Rewards.restDaysPerWeek - streak.restUsed) of \(Rewards.restDaysPerWeek) left this week.")
                        }
                    }
                    if let pace = c.paceLine {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            RingView(c.pressure >= .behind ? .drift : .on, color: c.pressure >= .behind ? Tokens.ink : Tokens.accent).frame(width: 14, height: 14)
                            Text(pace).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .contain)
        }
    }
}

struct GoalEditor: View {
    var prefs: Preferences
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily goal").font(Tokens.text(13, .semibold))
            Stepper(value: Binding(get: { prefs.dailyGoalMinutes }, set: { prefs.dailyGoalMinutes = $0 }), in: 15...480, step: 15) {
                Text("\(prefs.dailyGoalMinutes) minutes on task").font(Tokens.text(13)).monospacedDigit()
            }
            Text("Turn it off in Settings.").font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
        }
        .padding(16).frame(width: 240)
    }
}

/// The goal as the app's own ring: minutes inside, and the arc fills as the day goes. A reached goal says so in words.
struct GoalRing: View {
    var goal: Rewards.Goal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(Tokens.track, style: StrokeStyle(lineWidth: 12))
            Circle().trim(from: 0, to: max(goal.fraction > 0 ? 0.012 : 0, goal.fraction))
                .stroke(Tokens.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: goal.fraction)
            VStack(spacing: 0) {
                Text("\(goal.minutes)").font(Tokens.rounded(38, .semibold)).monospacedDigit()
                Text(goal.reached ? "goal reached" : "of \(goal.goalMinutes) min").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
            }
        }
        .accessibilityElement().accessibilityLabel("Daily goal").accessibilityValue("\(goal.minutes) of \(goal.goalMinutes) minutes")
    }
}

/// The three steps behind every call, one line each, behind a button instead of a block of text on the page.
struct HowDecidesButton: View {
    @State private var open = false
    var body: some View {
        Button { open = true } label: { Label("How Focus decides", systemImage: "info.circle").font(Tokens.text(13, .medium)).foregroundStyle(Tokens.ink2) }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 14) {
                    step("It reads the window", "The app, window title and page or file address, on this Mac. The words on screen too, if you turn that on.")
                    step("It compares with your task", "Words the window shares with your task count at once. The model judges the rest by meaning.")
                    step("It waits to be sure", "Not sure does nothing. A nudge needs two checks that agree and a drift that lasts.")
                    Text("Apple's on-device model can be wrong.").font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
                }
                .padding(18).frame(width: 320)
            }
    }
    func step(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Tokens.text(13, .semibold))
            Text(text).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// First day only: the three steps behind every call, under the start field, so the first screen explains itself without a paragraph.
/// Gone after the first session or when hidden.
struct HowItWorks: View {
    @Bindable var c: SessionController
    /// First run only: the three steps arrive one after another, reading order, once.
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "How Focus works")
                Spacer()
                Button("Hide") { c.prefs.introSeen = true }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
            HStack(alignment: .top, spacing: 14) {
                step("text.cursor", "Say what you are working on", "One line is enough. Focus keeps it as a project for next time.").arrive(0, shown, reduceMotion)
                step("macwindow", "It compares the window in front", "The app, the title and the page, read on this Mac. Words that match your task count at once.").arrive(1, shown, reduceMotion)
                step("hand.raised", "Not sure does nothing", "A nudge needs two checks that agree and a drift that lasts. The model can be wrong.").arrive(2, shown, reduceMotion)
            }
        }
        .onAppear { shown = true }
    }
    func step(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Tokens.accent)
                .frame(width: 32, height: 32).background(Circle().fill(Tokens.accentSoft)).accessibilityHidden(true)
            Text(title).font(Tokens.text(13.5, .semibold))
            Text(text).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tokens.well))
        .accessibilityElement(children: .combine)
    }
}

/// SF Symbols' draw-on where the system has it (macOS 26); earlier systems simply show the symbol.
struct DrawOn: ViewModifier {
    var hidden: Bool
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.symbolEffect(.drawOn, isActive: hidden) } else { content }
    }
}

extension View {
    /// One of a few items arriving in order: rises a few points and fades in, 60 ms after the one before. Reduce Motion: a plain fade.
    func arrive(_ index: Int, _ shown: Bool, _ reduce: Bool) -> some View {
        opacity(shown ? 1 : 0).offset(y: shown || reduce ? 0 : 8)
            .animation((reduce ? Motion.reduced : Motion.out(0.42)).delay(reduce ? 0 : 0.18 + Double(index) * 0.06), value: shown)
    }
}
