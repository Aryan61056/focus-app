import SwiftUI
import FocusBrain

// The pieces of Today between sessions.

/// The start surface. One field, Return to begin. With no text, Return continues the last project, so a returning user presses one key.
struct StartCard: View {
    @Bindable var c: SessionController
    @Binding var showStart: Bool
    var intro: Bool
    @State private var task = ""
    @State private var timed = false
    @State private var minutes = 50
    @FocusState private var focused: Bool
    /// Start was pressed on a name close to an older project: ask whether to continue that one before anything is created.
    @State private var asking = false

    var parsed: (task: String, minutes: Int?) { StartSheet.parse(task) }
    var projects: [Project] { c.store?.projects ?? [] }
    /// Older projects the typed name looks like (never when it matches one exactly).
    var similar: [Project] { ProjectMatch.similar(to: parsed.task, in: projects, limit: 1) }
    var existing: Project? { ProjectMatch.exact(parsed.task, in: projects) }
    var last: Project? { StartSheet.lastProject(c.store) }
    var canStart: Bool { !parsed.task.isEmpty || last != nil }

    var body: some View {
        Tile(padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(intro ? "Your first session" : "What are you working on?").font(Tokens.text(14, .semibold))
                    HStack(spacing: 10) {
                        TextField(last?.name ?? "Lab report on pendulums", text: $task)
                            .textFieldStyle(.plain).font(Tokens.rounded(20, .medium))
                            .padding(.horizontal, 16).frame(height: 56)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tokens.window))
                            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(focused ? Tokens.accent : Tokens.line, lineWidth: focused ? 1.5 : 1) }
                            .focused($focused).onSubmit { start() }
                            .onChange(of: task) { _, _ in asking = false }
                        Button { start() } label: { Text(parsed.task.isEmpty && last != nil ? "Continue" : "Start").frame(minWidth: 64) }
                            .buttonStyle(FocusButtonStyle(.primary)).controlSize(.large).frame(height: 56)
                            .disabled(!canStart).keyboardShortcut(.defaultAction)
                    }
                    hint
                }
                modeRow
                pickUp
                if c.prefs.practiceActive && !intro {
                    HStack(spacing: 8) {
                        Image(systemName: "eye").foregroundStyle(Tokens.ink2)
                        Text("Practice mode: Focus watches but will not interrupt. \(c.prefs.practiceSessionsLeft) practice \(c.prefs.practiceSessionsLeft == 1 ? "session" : "sessions") left.")
                            .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
                        Button("Nudge me now") { c.prefs.turnNudgesOnNow() }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                }
            }
        }
        .onAppear { focused = true }
    }

    /// One calm line under the field: what Return will do.
    @ViewBuilder var hint: some View {
        if asking, let p = similar.first {
            // The question. Nothing has been created yet; either answer starts the session.
            VStack(alignment: .leading, spacing: 10) {
                Text("You worked on \u{201C}\(p.name)\u{201D}\(Self.when(p, c.store)). Continue it, or start \u{201C}\(parsed.task)\u{201D} as a new project?")
                    .font(Tokens.text(13.5)).fixedSize(horizontal: false, vertical: true)
                if !p.nextStep.isEmpty { Text("Next: \(p.nextStep)").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).lineLimit(1) }
                HStack(spacing: 8) {
                    Button { start(continuing: p) } label: { Text("Continue \u{201C}\(p.name)\u{201D}").lineLimit(1) }.buttonStyle(FocusButtonStyle(.primary, small: true))
                    Button { start(forceNew: true) } label: { Text("Start new").lineLimit(1) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Tokens.accentSoft))
        } else if let m = parsed.minutes, existing == nil, let p = similar.first {
            Text("Looks like \u{201C}\(p.name)\u{201D}. Return asks before starting \(m) minutes on a new project.").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
        } else if let m = parsed.minutes {
            Text("Return starts a \(m) minute session on \u{201C}\(parsed.task)\u{201D}.").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
        } else if parsed.task.isEmpty, let p = last {
            Text(p.nextStep.isEmpty ? "Return continues \u{201C}\(p.name)\u{201D}." : "Return continues \u{201C}\(p.name)\u{201D}. Next: \(p.nextStep)")
                .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).lineLimit(1)
        } else if let p = existing {
            Text(p.nextStep.isEmpty ? "Return continues \u{201C}\(p.name)\u{201D}." : "Return continues \u{201C}\(p.name)\u{201D}. Next: \(p.nextStep)")
                .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).lineLimit(1)
        } else if let p = similar.first {
            HStack(spacing: 8) {
                Text("Did you mean \u{201C}\(p.name)\u{201D}?").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).lineLimit(1)
                Button("Use it") { task = p.name + (parsed.minutes.map { " \($0)" } ?? "") }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        } else if !parsed.task.isEmpty, !projects.isEmpty {
            Text("New project. You can describe it later under Projects.").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
        }
    }

    var modeRow: some View {
        HStack(spacing: 8) {
            let typed = parsed.minutes != nil
            chip("Open", on: !timed && !typed) { timed = false }
            chip("Timed", on: timed || typed) { timed = true }
            if timed && !typed {
                Picker("Length", selection: $minutes) { ForEach([25, 50, 90], id: \.self) { Text("\($0) min").tag($0) } }
                    .pickerStyle(.menu).labelsHidden().frame(width: 96)
            }
            Spacer()
            Button("More options") { showStart = true }.buttonStyle(FocusButtonStyle(.plain, small: true)).keyboardShortcut("n")
        }
    }

    @ViewBuilder var pickUp: some View {
        if let projects = c.store?.projects.prefix(3), !projects.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick up").font(Tokens.text(12.5, .medium)).foregroundStyle(Tokens.ink2)
                HStack(spacing: 10) {
                    ForEach(Array(projects)) { p in ProjectChip(c: c, project: p, onStart: { markSeen() }) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    func markSeen() { c.prefs.introSeen = true }

    /// What Return does. Typed text starts that task (a trailing number makes it timed); an empty field continues the last project.
    struct Plan: Equatable { var task: String; var projectId: UUID?; var mode: Mode; var duration: Double? }
    static func plan(text: String, timed: Bool, minutes: Int, last: Project?) -> Plan? {
        let p = StartSheet.parse(text)
        if p.task.isEmpty { return last.map { Plan(task: $0.name, projectId: $0.id, mode: .open, duration: nil) } }
        let isTimed = timed || p.minutes != nil
        return Plan(task: p.task, projectId: nil, mode: isTimed ? .timed : .open, duration: isTimed ? Double((p.minutes ?? minutes) * 60) : nil)
    }

    /// "3 days ago" style note for the question.
    static func when(_ p: Project, _ store: DataStore?) -> String {
        guard let s = store?.sessions(for: p.id).first else { return "" }
        return " " + s.start.formatted(.relative(presentation: .named))
    }

    /// Return. A name close to an older project is asked about first (once per edit of the field); an exact name just continues that project.
    func start(continuing project: Project? = nil, forceNew: Bool = false) {
        guard let p = Self.plan(text: task, timed: timed, minutes: minutes, last: last) else { return }
        if project == nil, !forceNew, !asking, p.projectId == nil, existing == nil, !similar.isEmpty { asking = true; return }
        markSeen()
        asking = false
        c.begin(task: project?.name ?? p.task, mode: p.mode, duration: p.duration, projectId: project?.id ?? p.projectId ?? existing?.id, autoTick: true)
    }

    func chip(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(ChoiceStyle(on: on))
    }
}

/// A project you can pick up with one click: its name, and either the next step you left or when you last worked on it.
struct ProjectChip: View {
    @Bindable var c: SessionController
    var project: Project
    var onStart: () -> Void
    @State private var hover = false

    var body: some View {
        let sessions = c.store?.sessions(for: project.id) ?? []
        let detail = project.nextStep.isEmpty ? (sessions.first.map { $0.start.formatted(.relative(presentation: .named)) } ?? "No sessions yet") : "Next: \(project.nextStep)"
        Button { onStart(); c.begin(task: project.name, projectId: project.id, autoTick: true) } label: {
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
    var body: some View {
        if let s = c.summary {
            Tile {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Session finished").font(Tokens.rounded(18, .semibold))
                        Spacer()
                    }
                    Text(sentence(s)).font(Tokens.text(14)).foregroundStyle(Tokens.ink2)
                    if let h = c.highlight { HighlightLine(highlight: h) }
                    RecapBlock(c: c)
                    if let p = c.projectForNote { PickUpNote(c: c, project: p) }
                    if c.askLoudness {
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
            }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "How Focus works")
                Spacer()
                Button("Hide") { c.prefs.introSeen = true }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
            HStack(alignment: .top, spacing: 14) {
                step("text.cursor", "Say what you are working on", "One line is enough. Focus keeps it as a project for next time.")
                step("macwindow", "It compares the window in front", "The app, the title and the page, read on this Mac. Words that match your task count at once.")
                step("hand.raised", "Not sure does nothing", "A nudge needs two checks that agree and a drift that lasts. The model can be wrong.")
            }
        }
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
