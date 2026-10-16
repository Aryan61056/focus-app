import SwiftUI
import FocusBrain
import FocusJudge

public struct StartSheet: View {
    @Bindable var c: SessionController
    @Binding var isPresented: Bool
    @State private var task = ""
    @State private var timed = false
    @State private var minutes = 50
    @FocusState private var focused: Bool
    /// A suggestion the user accepted: its "what counts" line is saved on the project only if they start with that exact task.
    @State private var accepted: Sharpened?
    /// Start was pressed on a name close to an older project: ask whether to continue that one before anything is created, as the start field does.
    @State private var asking = false

    /// Level 0 start (PLAN 4.8): the project worked on last, so a returning user only presses Enter.
    static func lastProject(_ store: DataStore?) -> Project? {
        guard let store, let r = store.sessions.max(by: { $0.start < $1.start }) else { return nil }
        return store.project(r.projectId)
    }

    public init(controller: SessionController, isPresented: Binding<Bool>) { self.c = controller; self._isPresented = isPresented }
    /// Snapshot only: a name already typed, and the near-duplicate question already asked.
    init(controller: SessionController, typed: String, asking: Bool) {
        self.c = controller; self._isPresented = .constant(true); self._task = State(initialValue: typed); self._asking = State(initialValue: asking)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("What are you working on?").font(Tokens.rounded(.title3, .semibold))
            TextField("Lab report on pendulums", text: $task)
                .font(Tokens.text(.headline)).wellField(height: 44, focused: focused)
                .focused($focused).onSubmit { start() }
                .onExitCommand { isPresented = false }
            coach
            if let m = parsed.minutes { Text("Timed session, \(m) minutes, on \u{201C}\(parsed.task)\u{201D}.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
            if let p = Self.lastProject(c.store), p.name == task, !p.nextStep.isEmpty {
                Label("Next step: \(p.nextStep)", systemImage: "arrow.turn.down.right").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            }
            if asking, let near = Self.askAbout(trimmed, in: c.store?.projects ?? []) {
                // The question. Nothing has been created yet; either answer starts the session.
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("You worked on \u{201C}\(near.name)\u{201D}\(StartCard.when(near, c.store)). Continue it, or start \u{201C}\(trimmed)\u{201D} as a new project?")
                        .font(Tokens.text(.body)).fixedSize(horizontal: false, vertical: true)
                    if !near.nextStep.isEmpty { Text("Next: \(near.nextStep)").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).lineLimit(1) }
                    HStack(spacing: Space.xs) {
                        Button { start(continuing: near) } label: { Text("Continue \u{201C}\(near.name)\u{201D}").lineLimit(1) }.buttonStyle(FocusButtonStyle(.primary, small: true))
                        Button { start(continuing: nil, forceNew: true) } label: { Text("Start new").lineLimit(1) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                }
                .padding(Space.s).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.accentSoft))
            } else if let near = Self.askAbout(trimmed, in: c.store?.projects ?? []) {
                // Close to an older project: offer to continue it instead of quietly starting a second one.
                HStack(spacing: Space.xs) {
                    Text("Did you mean").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                    HStack(spacing: 2) {
                        chip("\u{201C}\(near.name)\u{201D}", on: false) { task = near.name + (parsed.minutes.map { " \($0)" } ?? "") }
                        Text("?").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                    }
                }.lineLimit(1)
            } else if let line = Self.confirmLine(task: trimmed, project: c.store.flatMap { ProjectMatch.exact(trimmed, in: $0.projects) }) {
                Text(line).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            } else if let recent = c.store?.projects.prefix(3), !recent.isEmpty {
                HStack(spacing: Space.xs) {
                    Text("Continue").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                    ForEach(Array(recent)) { p in chip(p.name, on: false) { task = p.name } }
                }.lineLimit(1)
            }
            HStack(spacing: Space.xs) {
                // A typed length ("essay 25") wins, so the chips show what will actually start.
                let typed = parsed.minutes != nil
                chip("Open", on: !timed && !typed) { timed = false }
                chip("Timed", on: timed || typed) { timed = true }
                if timed && !typed {
                    Picker("Length", selection: $minutes) { ForEach([25, 50, 90], id: \.self) { Text("\($0) min").tag($0) } }
                        .pickerStyle(.menu).labelsHidden().frame(width: 100)
                }
            }
            if c.prefs.practiceActive {
                HStack(alignment: .top, spacing: Space.s) {
                    Label("Practice mode: Focus watches but will not interrupt you. \(c.prefs.practiceSessionsLeft) practice session\(c.prefs.practiceSessionsLeft == 1 ? "" : "s") left.", systemImage: "eye")
                        .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Nudge me now") { c.prefs.turnNudgesOnNow() }.buttonStyle(FocusButtonStyle(.plain, small: true))
                }
            }
            HStack {
                Button("Start") { start() }.buttonStyle(FocusButtonStyle(.primary, expand: true)).disabled(trimmed.isEmpty)
                    .keyboardShortcut(.defaultAction)
                Button("Cancel") { isPresented = false }.buttonStyle(FocusButtonStyle(.plain)).keyboardShortcut(.cancelAction)
            }
        }
        .padding(Space.xl).frame(width: 480)
        // The sheet grows and shrinks as lines come and go (the coach, the length picker, the hint), never jumps.
        .motion(Motion.out(0.24), value: c.sharpened)
        .motion(Motion.out(0.24), value: timed)
        .motion(Motion.out(0.24), value: parsed.minutes)
        .onChange(of: task) { _, _ in asking = false; if c.sharpened.value != nil || c.sharpened == .failed { c.clearSharpened() } }
        .onDisappear { c.clearSharpened() }
        .onAppear {
            focused = true
            if task.isEmpty, let p = Self.lastProject(c.store) { task = p.name }
        }
    }

    /// Task coach: optional, one button, and nothing changes until the user accepts the suggestion.
    @ViewBuilder var coach: some View {
        switch c.sharpened {
        case .idle:
            if c.aiAvailable && trimmed.count >= 3 && accepted == nil {
                Button { c.sharpenTask(trimmed) } label: { Label("Suggest a clearer task", systemImage: "sparkles") }
                    .buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        case .working:
            HStack(spacing: Space.xs) { ThinkingDot(); Text("Thinking about it on this Mac").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
        case .failed:
            Text("Focus has no suggestion right now. Your task is fine as it is.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        case .ready(let s):
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack { Text("Suggestion").font(Tokens.text(.body, .semibold)); AITag() }
                Text(s.task).font(Tokens.text(.callout, .medium))
                if !s.counts.isEmpty { Text("Counts as on task: \(s.counts)").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: Space.xs) {
                    Button("Use this") { task = s.task; accepted = s; c.clearSharpened() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                    Button("Keep mine") { c.clearSharpened() }.buttonStyle(FocusButtonStyle(.plain, small: true))
                }
            }
            .padding(Space.s).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
        }
    }

    /// One calm line under the task: what Focus will compare windows with. Nil until something is typed.
    static func confirmLine(task: String, project: Project?) -> String? {
        guard !task.isEmpty else { return nil }
        guard let p = project else { return "New project. Focus compares each window with this task. You can describe it later under Projects." }
        let ctx = p.context.trimmingCharacters(in: .whitespacesAndNewlines)
        if ctx.isEmpty { return "Focus knows this project. A line about it under Projects helps it decide." }
        let short = ctx.count > 70 ? String(ctx.prefix(67)) + "..." : ctx
        return "Focus will use what you wrote: \u{201C}\(short)\u{201D}"
    }

    /// "Calc homework 50" or "essay 25 min" start a timed session: a trailing number from 5 to 240, with an optional "m", "min" or "minutes".
    static func parse(_ text: String) -> (task: String, minutes: Int?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let re = try? NSRegularExpression(pattern: #"^(.*\S)\s+(\d{1,3})\s*(?:m|min|mins|minutes)?$"#, options: [.caseInsensitive]),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), m.numberOfRanges == 3,
              let a = Range(m.range(at: 1), in: t), let b = Range(m.range(at: 2), in: t), let n = Int(t[b]), (5...240).contains(n) else { return (t, nil) }
        return (String(t[a]), n)
    }

    var parsed: (task: String, minutes: Int?) { Self.parse(task) }
    var trimmed: String { parsed.task }

    /// The older project to ask about before starting `task`: one the name looks like, unless the name is a project's exactly. Nil starts at once.
    static func askAbout(_ task: String, in projects: [Project]) -> Project? {
        guard !task.isEmpty, ProjectMatch.exact(task, in: projects) == nil else { return nil }
        return ProjectMatch.similar(to: task, in: projects, limit: 1).first
    }

    /// Start. A name close to an older project is asked about first (once per edit of the field); a second Start makes it new, as typed.
    func start() { start(continuing: nil) }
    func start(continuing project: Project?, forceNew: Bool = false) {
        guard !trimmed.isEmpty else { return }
        if project == nil, !forceNew, !asking, Self.askAbout(trimmed, in: c.store?.projects ?? []) != nil { asking = true; return }
        let typedMinutes = parsed.minutes
        let isTimed = timed || typedMinutes != nil
        if project == nil, let a = accepted, a.task == trimmed { c.saveContextIfEmpty(task: trimmed, context: a.counts) }
        asking = false
        c.begin(task: project?.name ?? trimmed, mode: isTimed ? .timed : .open, duration: isTimed ? Double((typedMinutes ?? minutes) * 60) : nil,
                projectId: project?.id, autoTick: true)
        isPresented = false
    }

    func chip(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(ChoiceStyle(on: on))
    }
}
