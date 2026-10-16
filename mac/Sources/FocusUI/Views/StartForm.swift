import SwiftUI
import FocusJudge

/// Both entry surfaces host this form; all choices live in the controller's shared draft.
struct StartForm: View {
    @Bindable var c: SessionController
    var didStart: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var last: Project? { StartSheet.lastProject(c.store) }
    var parsed: (task: String, minutes: Int?) { StartSheet.parse(c.startDraft.task) }
    var canStart: Bool { (!parsed.task.isEmpty || last != nil) && c.startDraft.done.count <= 240 }
    var body: some View {
        @Bindable var draft = c.startDraft
        VStack(alignment: .leading, spacing: 16) {
            Text("What are you working on?").font(Tokens.rounded(20))
            HStack(spacing: 10) {
                TextField("Task", text: $draft.task, prompt: Text(last?.name ?? "Lab report on pendulums").foregroundStyle(Tokens.ink2))
                    .textFieldStyle(.plain).font(Tokens.text(16)).padding(14).background(Tokens.well, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? Tokens.accent : Tokens.line, lineWidth: focused ? 2 : 1) }
                    .focused($focused).onSubmit(start).accessibilityLabel("Your task").help("You can add a length, like essay 25")
                Button(parsed.task.isEmpty && last != nil ? "Continue" : "Start", action: start)
                    .buttonStyle(FocusButtonStyle(.primary)).disabled(!canStart).keyboardShortcut(.defaultAction)
            }
            hint
            if let minutes = parsed.minutes {
                HStack {
                    Text("\(minutes) minutes").font(Tokens.text(13)).foregroundStyle(Tokens.ink2)
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
                            Text(Calendar.current.isDate(end, inSameDayAs: c.date()) ? "Today" : "Tomorrow").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
                        }
                    }.transition(.rise(reduce: reduceMotion))
                }
            }
            DisclosureGroup("Optional", isExpanded: $draft.extras) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("What would done look like?", text: $draft.done, prompt: Text("What would done look like?").foregroundStyle(Tokens.ink2))
                        .textFieldStyle(.roundedBorder).accessibilityLabel("What would done look like?").help("Saved on this Mac with your session")
                    if draft.done.count > 240 { Text("Keep this under 240 characters.").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
                    coach
                    if c.prefs.practiceActive {
                        HStack { Text("Practice mode: no nudges.").font(Tokens.text(12.5)); Spacer(); Button("Nudge me now") { c.prefs.turnNudgesOnNow() } }
                    }
                }.padding(.top, 10)
            }.font(Tokens.text(13)).tint(Tokens.ink2)
            if let projects = c.store?.projects.prefix(3), !projects.isEmpty {
                HStack(spacing: 8) {
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
        }
        .task {
            let chosenProject = parsed.task.isEmpty ? last : c.store?.projects.first { $0.name.caseInsensitiveCompare(parsed.task) == .orderedSame }
            if draft.done.isEmpty, let goal = chosenProject?.carriedGoal { draft.done = goal; draft.extras = true }
            await Task.yield(); focused = true
        }
        .onDisappear { c.clearSharpened() }
    }
    func start() { if c.startWithDraft() { didStart() } }
    /// One calm line under the field: what Return will do, and the next step left on that project.
    @ViewBuilder var hint: some View {
        let named = c.store?.projects.first { $0.name.caseInsensitiveCompare(parsed.task) == .orderedSame }
        if parsed.task.isEmpty, let p = last {
            Text(p.nextStep.isEmpty ? "Return continues \u{201C}\(p.name)\u{201D}." : "Return continues \u{201C}\(p.name)\u{201D}. Next: \(p.nextStep)")
                .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).lineLimit(1)
        } else if let p = named, !p.nextStep.isEmpty {
            Label("Next step: \(p.nextStep)", systemImage: "arrow.turn.down.right").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).lineLimit(2)
        } else if !parsed.task.isEmpty, named == nil, c.store?.projects.isEmpty == false {
            Text("New project. You can describe it later under Projects.").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
        }
    }
    @ViewBuilder var coach: some View {
        switch c.sharpened {
        case .idle:
            if c.aiAvailable && parsed.task.count >= 3 && c.startDraft.accepted == nil {
                Button { c.sharpenTask(parsed.task) } label: { Label("Suggest a clearer task", systemImage: "sparkles") }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        case .working: HStack { ThinkingDot(); Text("Thinking about it on this Mac").font(Tokens.text(12.5)) }
        case .failed: Text("Focus has no suggestion right now. Your task is fine as it is.").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
        case .ready(let suggestion):
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Suggestion").font(Tokens.text(13, .semibold)); AITag() }
                Text(suggestion.task).font(Tokens.text(14, .medium))
                if !suggestion.counts.isEmpty { Text("Counts as on task: \(suggestion.counts)").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true) }
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
                Label(c.sessionGoal, systemImage: c.goalDisposition == "done" ? "checkmark.circle.fill" : "circle").font(Tokens.text(14, .medium))
                if c.goalDisposition == nil {
                    HStack {
                        Button("Done") { c.resolveSessionGoal(done: true) }.buttonStyle(FocusButtonStyle(.secondary, small: true)).help("Mark your result done")
                        Button("Carry forward") { c.resolveSessionGoal(done: false) }.buttonStyle(FocusButtonStyle(.plain, small: true)).help("Offer this result in your next session")
                    }
                } else { Text(c.goalDisposition == "done" ? "Done for this session." : "Ready for your next session.").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
            }.contentTransition(.opacity).motion(Motion.notchSettle, value: c.goalDisposition)
        }
    }
}
