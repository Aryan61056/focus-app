import SwiftUI
import FocusBrain

public struct StartSheet: View {
    @Bindable var c: SessionController
    @Binding var isPresented: Bool
    @State private var task = ""
    @State private var timed = false
    @State private var minutes = 50
    @FocusState private var focused: Bool

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
                chip("Open", on: !timed) { timed = false }
                chip("Timed", on: timed) { timed = true }
                if timed {
                    Picker("Length", selection: $minutes) { ForEach([25, 50, 90], id: \.self) { Text("\($0) min").tag($0) } }
                        .pickerStyle(.menu).labelsHidden().frame(width: 100)
                }
            }
            if c.prefs.practiceActive {
                Label("Practice mode: Focus watches but will not interrupt you. \(c.prefs.practiceSessionsLeft) practice session\(c.prefs.practiceSessionsLeft == 1 ? "" : "s") left.", systemImage: "eye")
                    .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Start") { start() }.buttonStyle(FocusButtonStyle(.primary, expand: true)).disabled(trimmed.isEmpty)
                    .keyboardShortcut(.defaultAction)
                Button("Cancel") { isPresented = false }.buttonStyle(FocusButtonStyle(.plain)).keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 480)
        .onAppear {
            focused = true
            if task.isEmpty, let p = Self.lastProject(c.store) { task = p.name }
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

    var trimmed: String { task.trimmingCharacters(in: .whitespacesAndNewlines) }

    func start() {
        guard !trimmed.isEmpty else { return }
        c.begin(task: trimmed, mode: timed ? .timed : .open, duration: timed ? Double(minutes * 60) : nil, autoTick: true)
        isPresented = false
    }

    func chip(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(.plain).font(Tokens.text(12.5, .medium)).padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill(on ? Tokens.accentSoft : Tokens.control))
            .overlay { if on { Capsule().strokeBorder(Tokens.accent, lineWidth: 1.5) } }
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}
