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

    /// Level 0 start (PLAN 4.8): the project worked on last, so a returning user only presses Enter.
    static func lastProject(_ store: DataStore?) -> Project? {
        guard let store, let r = store.sessions.max(by: { $0.start < $1.start }) else { return nil }
        return store.project(r.projectId)
    }

    public init(controller: SessionController, isPresented: Binding<Bool>) { self.c = controller; self._isPresented = isPresented }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What are you working on?").font(Tokens.rounded(22, .semibold))
            TextField("Lab report on pendulums", text: $task)
                .textFieldStyle(.plain).font(Tokens.text(16)).padding(.horizontal, 14).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.control))
                .focused($focused).onSubmit(start)
                .onExitCommand { isPresented = false }
            coach
            if let m = parsed.minutes { Text("Timed session, \(m) minutes, on \u{201C}\(parsed.task)\u{201D}.").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
            if let p = Self.lastProject(c.store), p.name == task, !p.nextStep.isEmpty {
                Label("Next step: \(p.nextStep)", systemImage: "arrow.turn.down.right").font(Tokens.text(13)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            }
            if let line = Self.confirmLine(task: trimmed, project: c.store?.projects.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                Text(line).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            } else if let recent = c.store?.projects.prefix(3), !recent.isEmpty {
                HStack(spacing: 6) {
                    Text("Continue").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
                    ForEach(Array(recent)) { p in chip(p.name, on: false) { task = p.name } }
                }.lineLimit(1)
            }
            HStack(spacing: 6) {
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
                HStack(alignment: .top, spacing: 10) {
                    Label("Practice mode: Focus watches but will not interrupt you. \(c.prefs.practiceSessionsLeft) practice session\(c.prefs.practiceSessionsLeft == 1 ? "" : "s") left.", systemImage: "eye")
                        .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
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
        .padding(24).frame(width: 480)
        .onChange(of: task) { _, _ in if c.sharpened.value != nil || c.sharpened == .failed { c.clearSharpened() } }
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
            HStack(spacing: 8) { ThinkingDot(); Text("Thinking about it on this Mac").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
        case .failed:
            Text("Focus has no suggestion right now. Your task is fine as it is.").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
        case .ready(let s):
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Suggestion").font(Tokens.text(13, .semibold)); AITag() }
                Text(s.task).font(Tokens.text(14, .medium))
                if !s.counts.isEmpty { Text("Counts as on task: \(s.counts)").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: 8) {
                    Button("Use this") { task = s.task; accepted = s; c.clearSharpened() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                    Button("Keep mine") { c.clearSharpened() }.buttonStyle(FocusButtonStyle(.plain, small: true))
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.window2))
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

    func start() {
        guard !trimmed.isEmpty else { return }
        let typedMinutes = parsed.minutes
        let isTimed = timed || typedMinutes != nil
        if let a = accepted, a.task == trimmed { c.saveContextIfEmpty(task: trimmed, context: a.counts) }
        c.begin(task: trimmed, mode: isTimed ? .timed : .open, duration: isTimed ? Double((typedMinutes ?? minutes) * 60) : nil, autoTick: true)
        isPresented = false
    }

    func chip(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(ChoiceStyle(on: on))
    }
}
