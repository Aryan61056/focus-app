import SwiftUI
import FocusBrain

// The pieces of Today between sessions.

/// The start surface. One field, Return to begin. With no text, Return continues the last project, so a returning user presses one key.
/// The form itself is shared with the start sheet (`StartForm`).
struct StartCard: View {
    @Bindable var c: SessionController
    @Binding var showStart: Bool
    var intro: Bool
    var body: some View {
        Tile(padding: 24) {
            VStack(alignment: .leading, spacing: Space.m) {
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

/// A project you can pick up with one click: its name and when you last worked on it.
struct ProjectChip: View {
    @Bindable var c: SessionController
    var project: Project
    var onStart: () -> Void
    @State private var hover = false

    var body: some View {
        let sessions = c.store?.sessions(for: project.id) ?? []
        let detail = sessions.first.map { $0.start.formatted(.relative(presentation: .named)) } ?? "No sessions yet"
        Button { onStart(); _ = c.startWithDraft(task: project.name, projectId: project.id) } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Tokens.onAccent)
                    .frame(width: 24, height: 24).background(Circle().fill(Tokens.accent))
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).font(Tokens.text(.body, .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s).padding(.vertical, Space.xs).frame(maxWidth: .infinity, minHeight: 46, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(hover ? Tokens.controlHover : Tokens.control))
            .contentShape(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous))
        }
        .buttonStyle(.plain).onHover { hover = $0 }.disabled(c.isActive)
        .help(project.name)
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
            let settled = !c.shortSessionOffer && (c.sessionGoal.isEmpty || c.goalDisposition != nil)
            Tile {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Image(systemName: "checkmark.circle").font(.system(size: 17, weight: .semibold)).foregroundStyle(Tokens.accent)
                            .modifier(DrawOn(hidden: !drawn && !reduceMotion))
                            .accessibilityHidden(true)
                        Text("Session finished").font(Tokens.rounded(.title3, .semibold))
                        Spacer()
                    }
                    .task { try? await Task.sleep(for: .milliseconds(220)); drawn = true }
                    Text(sentence(s)).font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2)
                    if let h = c.highlight { HighlightLine(highlight: h) }
                    if c.shortSessionOffer {
                        FlowRow(spacing: Space.xs) {
                            Button("Keep going") { c.keepGoing() }.buttonStyle(FocusButtonStyle(.primary, small: true))
                            Button("Finish") { c.finishFiveMinutes() }.buttonStyle(FocusButtonStyle(.plain, small: true))
                        }
                    } else { SessionGoalResult(c: c) }
                    if settled { RecapBlock(c: c) }
                    if c.askLoudness && settled {
                        Divider().overlay(Tokens.line)
                        FlowRow(spacing: Space.xs) {
                            Text("Was Hushd too loud?").font(Tokens.text(.body, .semibold))
                            Button("Too quiet") { c.prefs.answerLoudness(.tooQuiet) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                            Button("About right") { c.prefs.answerLoudness(.aboutRight) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                            Button("Too loud") { c.prefs.answerLoudness(.tooLoud) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                        }
                    }
                }
                // A soft bloom of dots from the corner when the card arrives, so finishing feels marked without taking over the card.
                .background(alignment: .topTrailing) {
                    Halftone(pattern: .bloom(from: .topTrailing, aspect: 1.6), ripple: .onAppear, followsPointer: false)
                        .frame(width: 320, height: 200).offset(x: Space.l, y: -Space.l).allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
        }
    }
    func sentence(_ s: SessionSummary) -> String {
        let on = Int(((s.activeSeconds - s.offTopicSeconds - s.unsureSeconds) / 60).rounded())
        let slips = s.drifts == 0 ? "No slips." : (s.drifts == 1 ? "One slip." : "\(s.drifts) slips.")
        return "\(max(on, 0)) minutes on task. \(slips)"
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
            Panel { VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle(text: "Your day")
                    Spacer()
                    Text("\(durationText(total.onTaskSeconds)) on task \u{00B7} \(total.sessions) \(total.sessions == 1 ? "session" : "sessions") \u{00B7} \(total.slips == 0 ? "no slips" : (total.slips == 1 ? "1 slip" : "\(total.slips) slips"))")
                        .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
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
            Panel { VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle(text: "This week")
                    Spacer()
                    Text("\(durationText(week.reduce(0) { $0 + $1.hours } * 3600)) on task \u{00B7} longest on \(best.day.formatted(.dateTime.weekday(.wide)))")
                        .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
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
            // Flat, in the Focus panel: a heading, the ring and the week, no card around them.
            Group {
                VStack(spacing: Space.m) {
                    HStack {
                        Text("Today's goal").font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink2).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button { editing = true } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(Tokens.ink2).frame(width: 28, height: 28).contentShape(Rectangle()) }
                            .buttonStyle(.plain).help("Change the daily goal").accessibilityLabel("Change the daily goal")
                            .popover(isPresented: $editing, arrowEdge: .bottom) { GoalEditor(prefs: c.prefs) }
                    }
                    GoalRing(goal: goal).frame(width: 120 * TextScale.shared.factor, height: 120 * TextScale.shared.factor)   // grows with the text it holds
                    if !store.sessions.isEmpty {
                        VStack(spacing: Space.s) {
                            WeekStrip(week: streak.week)
                            Text(streak.current == 0 ? "Ready when you are" : (streak.current == 1 ? "1 focus day" : "\(streak.current) focus days in a row"))
                                .font(Tokens.text(.body, .semibold))
                                .help(streak.current == 0 ? "A focus day is \(Int(Rewards.focusDaySeconds / 60)) minutes on task." : "Rest days keep it going: \(Rewards.restDaysPerWeek - streak.restUsed) of \(Rewards.restDaysPerWeek) left this week.")
                        }
                    }
                    if let pace = c.paceLine {
                        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                            RingView(c.pressure >= .behind ? .drift : .on, color: c.pressure >= .behind ? Tokens.ink : Tokens.accent).frame(width: 14, height: 14)
                            Text(pace).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Daily goal").font(Tokens.text(.body, .semibold))
            Stepper(value: Binding(get: { prefs.dailyGoalMinutes }, set: { prefs.dailyGoalMinutes = $0 }), in: 15...480, step: 15) {
                Text("\(prefs.dailyGoalMinutes) minutes on task").font(Tokens.text(.body)).monospacedDigit()
            }
            Text("Turn it off in Settings.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        }
        .padding(Space.m).frame(width: 240)
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
                Text("\(goal.minutes)").font(Tokens.rounded(.display, .semibold)).monospacedDigit()
                Text(goal.reached ? "goal reached" : "of \(goal.goalMinutes) min").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
            }
        }
        .accessibilityElement().accessibilityLabel("Daily goal").accessibilityValue("\(goal.minutes) of \(goal.goalMinutes) minutes")
    }
}

/// The three steps behind every call, one line each, behind a button instead of a block of text on the page.
struct HowDecidesButton: View {
    @State private var open = false
    var body: some View {
        Button { open = true } label: { Label("How Hushd decides", systemImage: "info.circle").font(Tokens.text(.body, .medium)).foregroundStyle(Tokens.ink2) }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: Space.m) {
                    step("It reads the window", "The app, window title and page or file address, on this Mac. The words on screen too, if you turn that on.")
                    step("It compares with your task", "Words the window shares with your task count at once. The model judges the rest by meaning.")
                    step("It waits to be sure", "Not sure does nothing. A nudge needs two checks that agree and a drift that lasts.")
                    Text("Apple's on-device model can be wrong.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                }
                .padding(Space.l).frame(width: 320)
            }
    }
    func step(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Tokens.text(.body, .semibold))
            Text(text).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "How Hushd works")
                Spacer()
                Button("Hide") { c.prefs.introSeen = true }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
            // A real sequence, so it is numbered: one inset, three short steps, no grid of look-alike cards.
            Inset(padding: Space.l) {
                VStack(alignment: .leading, spacing: Space.m) {
                    step(1, "Say what you are working on", "Kept as a project for next time").arrive(0, shown, reduceMotion)
                    step(2, "It compares the window in front", "App, title and page, read on this Mac").arrive(1, shown, reduceMotion)
                    step(3, "Not sure does nothing", "It can be wrong, so a nudge needs a drift that lasts").arrive(2, shown, reduceMotion)
                }
            }
        }
        .onAppear { shown = true }
    }
    func step(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text("\(n)").font(Tokens.rounded(.body, .semibold)).foregroundStyle(Tokens.accentInk)
                .frame(width: 24, height: 24).background(Circle().fill(Tokens.accentSoft)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Tokens.text(.body, .semibold))
                Text(text).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
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
