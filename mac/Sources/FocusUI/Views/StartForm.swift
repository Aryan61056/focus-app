import SwiftUI
import FocusJudge

/// Both entry surfaces host this form; all choices live in the controller's shared draft.
struct StartForm: View {
    @Bindable var c: SessionController
    var didStart: () -> Void
    /// Where the page shows the model's suggestion itself (Today's "What Focus will look for"), the form does not offer it a second time.
    var showsCoach = true
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Start was pressed on a name close to an older project: ask whether to continue that one before anything is created.
    @State private var asking: Bool
    init(c: SessionController, asking: Bool = false, showsCoach: Bool = true, didStart: @escaping () -> Void) { self.c = c; self.didStart = didStart; self.showsCoach = showsCoach; _asking = State(initialValue: asking) }
    var projects: [Project] { c.store?.projects ?? [] }
    /// Older projects the typed name looks like (never when it matches one exactly).
    var similar: [Project] { ProjectMatch.similar(to: parsed.task, in: projects, limit: 1) }
    var existing: Project? { ProjectMatch.exact(parsed.task, in: projects) }
    var last: Project? { StartSheet.lastProject(c.store) }
    var parsed: (task: String, minutes: Int?) { StartSheet.parse(c.startDraft.task) }
    /// Up to three projects to start in one click, the one you worked on last first.
    var recent: [Project] { StartSheet.recentProjects(c.store) }
    /// The project Return will start: the one you named, or with nothing typed the one you worked on last.
    func isTarget(_ p: Project) -> Bool { parsed.task.isEmpty ? p.id == last?.id : parsed.task == p.name }
    func group<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Tokens.text(.caption, .medium)).foregroundStyle(Tokens.ink2)
            content()
        }
    }
    var canStart: Bool { (!parsed.task.isEmpty || last != nil) && c.startDraft.done.count <= 240 }
    var body: some View {
        @Bindable var draft = c.startDraft
        VStack(alignment: .leading, spacing: 16) {
            Text("What are you working on?").font(Tokens.rounded(.title3))
            // Side by side when the field keeps room to show a name; the button under it, at the right, when it would not.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { taskField(draft: $draft.task).frame(minWidth: 200 * TextScale.shared.factor); startButton }
                VStack(alignment: .trailing, spacing: 10) { taskField(draft: $draft.task); startButton }
            }
            hint
            if !recent.isEmpty {
                group("Recent") {
                    FlowRow(spacing: 8) {
                        ForEach(recent) { project in
                            Button(project.name) { draft.task = project.name; draft.done = project.carriedGoal ?? "" }
                                .buttonStyle(ChoiceStyle(on: isTarget(project))).lineLimit(1).help("Start with \(project.name)")
                        }
                    }
                }
            }
            group("How long") {
                if let minutes = parsed.minutes {
                    HStack {
                        Text("\(minutes) minutes").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                        Button("Change length") { draft.task = parsed.task }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                } else if draft.length == .until {
                    HStack {
                        DatePicker("Finish at", selection: $draft.until, displayedComponents: [.hourAndMinute]).datePickerStyle(.field)
                        if let end = draft.plan(now: c.date())?.deadline {
                            Text(Calendar.current.isDate(end, inSameDayAs: c.date()) ? "Today" : "Tomorrow").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                        }
                        Spacer()
                        Button("Use a length") { draft.length = .open }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }.transition(.rise(reduce: reduceMotion))
                } else {
                    lengthSlider
                }
            }
            DisclosureGroup("More options", isExpanded: $draft.extras) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("What would done look like?", text: $draft.done, prompt: Text("What would done look like?").foregroundStyle(Tokens.ink2))
                        .textFieldStyle(.roundedBorder).accessibilityLabel("What would done look like?").help("Saved on this Mac with your session")
                    if draft.done.count > 240 { Text("Keep this under 240 characters.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
                    if showsCoach { coach }
                    if c.prefs.practiceActive {
                        HStack { Text("Practice mode: no nudges.").font(Tokens.text(.caption)); Spacer(); Button("Nudge me now") { c.prefs.turnNudgesOnNow() } }
                    }
                }.padding(.top, 10)
            }.font(Tokens.text(.body)).tint(Tokens.ink2)
        }
        .motion(Motion.notchSettle, value: draft.length).motion(Motion.notchSettle, value: draft.extras)
        .motion(Motion.notchSettle, value: c.sharpened)
        .onChange(of: draft.task) { _, value in
            if draft.accepted?.task != value { draft.accepted = nil }
            c.clearSharpened()
            asking = false
        }
        .task {
            let chosenProject = parsed.task.isEmpty ? last : c.store?.projects.first { $0.name.caseInsensitiveCompare(parsed.task) == .orderedSame }
            if draft.done.isEmpty, let goal = chosenProject?.carriedGoal { draft.done = goal; draft.extras = true }
            // A person who runs timed sessions out of habit starts on their usual length; everyone else starts on Open.
            if !draft.lengthTouched, draft.length == .open, let usual = LengthStops.usualMinutes(from: c.store?.sessions ?? []) {
                draft.length = .minutes; draft.minutes = usual; draft.usualMinutes = usual
            }
            await Task.yield(); focused = true
        }
        .onDisappear { c.clearSharpened() }
    }
    /// One slider for how long: stops every five minutes at first, then wider, and Open (no timer) at the far end. It starts on the length this
    /// person usually picks once they have a habit of timed sessions; otherwise on Open.
    var stop: Binding<Double> {
        Binding(
            get: { Double(c.startDraft.length == .minutes ? LengthStops.nearest(c.startDraft.minutes) : LengthStops.open) },
            set: { value in
                let draft = c.startDraft, index = Int(value.rounded())
                draft.lengthTouched = true
                if index >= LengthStops.open { draft.length = .open } else { draft.length = .minutes; draft.minutes = LengthStops.minutes[index] }
            })
    }
    var lengthReadout: String { c.startDraft.length == .minutes ? LengthStops.describe(minutes: c.startDraft.minutes) : "No timer" }
    var lengthNote: String {
        let draft = c.startDraft
        guard draft.length == .minutes else { return "It ends when you end it." }
        if draft.minutes == 5 { return "A short start. When it ends you can keep going." }
        let end = c.date().addingTimeInterval(Double(draft.minutes) * 60).formatted(date: .omitted, time: .shortened)
        return "Ends at \(end)." + (!draft.lengthTouched && draft.usualMinutes == draft.minutes ? " Your usual length." : "")
    }
    var lengthSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(lengthReadout).font(Tokens.text(.headline).monospacedDigit()).contentTransition(.numericText())
                Spacer()
                Button("Until a time\u{2026}") { c.startDraft.length = .until; c.startDraft.lengthTouched = true }
                    .buttonStyle(FocusButtonStyle(.plain, small: true)).help("End at a time of day instead of after a length")
            }
            Slider(value: stop, in: 0...Double(LengthStops.open), step: 1) { Text("How long") } minimumValueLabel: {
                Text("5 min").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
            } maximumValueLabel: {
                Text("No timer").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
            }
            .labelsHidden().tint(Tokens.accent).accessibilityLabel("How long").accessibilityValue(lengthReadout)
            Text(lengthNote).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        }
        .motion(Motion.notchSettle, value: c.startDraft.minutes)
    }
    func taskField(draft: Binding<String>) -> some View {
        TextField("Task", text: draft, prompt: Text(last == nil ? "e.g. Lab report on pendulums" : "Or type a new task").foregroundStyle(Tokens.ink2))
            .textFieldStyle(.plain).font(Tokens.text(.headline)).padding(14).background(Tokens.well, in: RoundedRectangle(cornerRadius: Tokens.radiusCard))
            .overlay { RoundedRectangle(cornerRadius: Tokens.radiusCard).strokeBorder(focused ? Tokens.accent : Tokens.line, lineWidth: focused ? 2 : 1) }
            .focused($focused).onSubmit { start() }.accessibilityLabel("Your task").help(last.map { "Leave this empty and press Return to continue \($0.name). You can add a length, like essay 25." } ?? "You can add a length, like essay 25")
    }
    var startButton: some View {
        Button { start() } label: { Text(parsed.task.isEmpty && last != nil ? "Continue" : "Start").frame(minWidth: 64) }
            .buttonStyle(FocusButtonStyle(.primary)).disabled(!canStart).keyboardShortcut(.defaultAction)
    }
    /// Return. A name close to an older project is asked about first (once per edit of the field); an exact name just continues that project.
    func start(continuing project: Project? = nil, forceNew: Bool = false) {
        if project == nil, !forceNew, !asking, StartSheet.askAbout(parsed.task, in: projects) != nil { asking = true; return }
        asking = false
        // Continuing makes the draft's name the older project's, so the shared start finds it and keeps the draft's length and finish line.
        if let project { c.startDraft.task = project.name + (parsed.minutes.map { " \($0)" } ?? "") }
        if c.startWithDraft() { didStart() }
    }
    /// "3 days ago" style note for the question.
    static func when(_ p: Project, _ store: DataStore?) -> String {
        guard let s = store?.sessions(for: p.id).first else { return "" }
        return " " + s.start.formatted(.relative(presentation: .named))
    }
    /// One calm line under the field, only when there is something to say about the name you typed.
    @ViewBuilder var hint: some View {
        if asking, let p = similar.first {
            // The question. Nothing has been created yet; either answer starts the session.
            VStack(alignment: .leading, spacing: Space.s) {
                Text("You worked on \u{201C}\(p.name)\u{201D}\(Self.when(p, c.store)). Continue it, or start \u{201C}\(parsed.task)\u{201D} as a new project?")
                    .font(Tokens.text(.body)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.xs) {
                    Button { start(continuing: p) } label: { Text("Continue \u{201C}\(p.name)\u{201D}").lineLimit(1) }.buttonStyle(FocusButtonStyle(.primary, small: true))
                    Button { start(forceNew: true) } label: { Text("Start new").lineLimit(1) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                }
            }
            .padding(Space.s).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.accentSoft))
        } else if let p = similar.first, existing == nil {
            HStack(spacing: Space.xs) {
                Text("Did you mean \u{201C}\(p.name)\u{201D}?").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).lineLimit(1)
                Button("Use it") { c.startDraft.task = p.name + (parsed.minutes.map { " \($0)" } ?? "") }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        } else if !parsed.task.isEmpty, existing == nil, !projects.isEmpty {
            Text("New project. You can describe it later under Projects.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        }
    }
    @ViewBuilder var coach: some View {
        switch c.sharpened {
        case .idle:
            if c.aiAvailable && parsed.task.count >= 3 && c.startDraft.accepted == nil {
                Button { c.sharpenTask(parsed.task) } label: { Label("Suggest a clearer task", systemImage: "sparkles") }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        case .working: HStack { ThinkingDot(); Text("Thinking about it on this Mac").font(Tokens.text(.caption)) }
        case .failed: Text("Focus has no suggestion right now. Your task is fine as it is.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        case .ready(let suggestion):
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Suggestion").font(Tokens.text(.body, .semibold)); AITag() }
                Text(suggestion.task).font(Tokens.text(.callout, .medium))
                if !suggestion.counts.isEmpty { Text("Counts as on task: \(suggestion.counts)").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Button("Use this") { c.startDraft.task = suggestion.task; c.startDraft.accepted = suggestion; c.clearSharpened() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                    Button("Keep mine") { c.clearSharpened() }.buttonStyle(FocusButtonStyle(.plain, small: true))
                }
            }
        }
    }
}

struct SessionGoalResult: View {
    @Bindable var c: SessionController
    var body: some View {
        if !c.sessionGoal.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(c.sessionGoal, systemImage: c.goalDisposition == "done" ? "checkmark.circle.fill" : "circle").font(Tokens.text(.callout, .medium))
                if c.goalDisposition == nil {
                    HStack {
                        Button("Done") { c.resolveSessionGoal(done: true) }.buttonStyle(FocusButtonStyle(.secondary, small: true)).help("Mark your result done")
                        Button("Carry forward") { c.resolveSessionGoal(done: false) }.buttonStyle(FocusButtonStyle(.plain, small: true)).help("Offer this result in your next session")
                    }
                } else { Text(c.goalDisposition == "done" ? "Done for this session." : "Ready for your next session.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
            }.contentTransition(.opacity).motion(Motion.notchSettle, value: c.goalDisposition)
        }
    }
}
