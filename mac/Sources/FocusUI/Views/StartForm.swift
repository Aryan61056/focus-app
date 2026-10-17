import SwiftUI
import FocusJudge

/// Both entry surfaces host this form; all choices live in the controller's shared draft.
struct StartForm: View {
    @Bindable var c: SessionController
    var didStart: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Start was pressed on a name close to an older project: ask whether to continue that one before anything is created.
    @State private var asking: Bool
    init(c: SessionController, asking: Bool = false, didStart: @escaping () -> Void) { self.c = c; self.didStart = didStart; _asking = State(initialValue: asking) }
    var projects: [Project] { c.store?.projects ?? [] }
    /// Older projects the typed name looks like (never when it matches one exactly).
    var similar: [Project] { ProjectMatch.similar(to: parsed.task, in: projects, limit: 1) }
    var existing: Project? { ProjectMatch.exact(parsed.task, in: projects) }
    var last: Project? { StartSheet.lastProject(c.store) }
    var parsed: (task: String, minutes: Int?) { StartSheet.parse(c.startDraft.task) }
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
            if let minutes = parsed.minutes {
                HStack {
                    Text("\(minutes) minutes").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                    Button("Change length") { draft.task = parsed.task }.buttonStyle(FocusButtonStyle(.plain, small: true))
                }
            } else {
                Picker("Length", selection: $draft.length) { ForEach(StartLength.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    .help("Choose a short start, a timed session, a clock time or an open session")
                if draft.length == .until {
                    HStack {
                        DatePicker("Finish at", selection: $draft.until, displayedComponents: [.hourAndMinute]).datePickerStyle(.field)
                        Spacer()
                        if let end = draft.plan(now: c.date())?.deadline {
                            Text(Calendar.current.isDate(end, inSameDayAs: c.date()) ? "Today" : "Tomorrow").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                        }
                    }.transition(.rise(reduce: reduceMotion))
                }
            }
            DisclosureGroup("Optional", isExpanded: $draft.extras) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("What would done look like?", text: $draft.done, prompt: Text("What would done look like?").foregroundStyle(Tokens.ink2))
                        .textFieldStyle(.roundedBorder).accessibilityLabel("What would done look like?").help("Saved on this Mac with your session")
                    if draft.done.count > 240 { Text("Keep this under 240 characters.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
                    coach
                    if c.prefs.practiceActive {
                        HStack { Text("Practice mode: no nudges.").font(Tokens.text(.caption)); Spacer(); Button("Nudge me now") { c.prefs.turnNudgesOnNow() } }
                    }
                }.padding(.top, 10)
            }.font(Tokens.text(.body)).tint(Tokens.ink2)
            if let projects = c.store?.projects.prefix(3), !projects.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(Array(projects)) { project in
                        Button(project.name) { draft.task = project.name; draft.done = project.carriedGoal ?? "" }
                            .buttonStyle(ChoiceStyle(on: parsed.task == project.name)).lineLimit(1).help("Start with \(project.name)")
                    }
                }
            }
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
            await Task.yield(); focused = true
        }
        .onDisappear { c.clearSharpened() }
    }
    func taskField(draft: Binding<String>) -> some View {
        TextField("Task", text: draft, prompt: Text(last?.name ?? "Lab report on pendulums").foregroundStyle(Tokens.ink2))
            .textFieldStyle(.plain).font(Tokens.text(.headline)).padding(14).background(Tokens.well, in: RoundedRectangle(cornerRadius: Tokens.radiusCard))
            .overlay { RoundedRectangle(cornerRadius: Tokens.radiusCard).strokeBorder(focused ? Tokens.accent : Tokens.line, lineWidth: focused ? 2 : 1) }
            .focused($focused).onSubmit { start() }.accessibilityLabel("Your task").help("You can add a length, like essay 25")
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
    /// One calm line under the field: what Return will do.
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
        } else if parsed.task.isEmpty, let p = last {
            Text("Return continues \u{201C}\(p.name)\u{201D}.")
                .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).lineLimit(2)
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
