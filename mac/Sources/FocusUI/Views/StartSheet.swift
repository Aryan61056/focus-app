import SwiftUI
import FocusBrain

public struct StartSheet: View {
    @Bindable var c: SessionController
    @Binding var isPresented: Bool
    var asking = false
    public init(controller: SessionController, isPresented: Binding<Bool>) { c = controller; _isPresented = isPresented }
    /// Snapshot only: a name already typed, and the near-duplicate question already asked.
    init(controller: SessionController, typed: String, asking: Bool) {
        c = controller; _isPresented = .constant(true); self.asking = asking; controller.startDraft.task = typed
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StartForm(c: c, asking: asking) { isPresented = false }
            HStack { Spacer(); Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 520).onExitCommand { isPresented = false }
    }
    /// The projects to offer as one-click starts: the ones you worked on most recently first, then any never used, newest first.
    static func recentProjects(_ store: DataStore?, limit: Int = 3) -> [Project] {
        guard let store else { return [] }
        var lastUsed: [UUID: Date] = [:]
        for s in store.sessions { if let id = s.projectId, (lastUsed[id] ?? .distantPast) < s.start { lastUsed[id] = s.start } }
        let used = store.projects.filter { lastUsed[$0.id] != nil }.sorted { (lastUsed[$0.id] ?? .distantPast) > (lastUsed[$1.id] ?? .distantPast) }
        return Array((used + store.projects.filter { lastUsed[$0.id] == nil }).prefix(limit))
    }
    static func lastProject(_ store: DataStore?) -> Project? {
        guard let store, let r = store.sessions.max(by: { $0.start < $1.start }) else { return nil }
        return store.project(r.projectId)
    }

    /// The older project to ask about before starting `task`: one the name looks like, unless the name is a project's exactly. Nil starts at once.
    static func askAbout(_ task: String, in projects: [Project]) -> Project? {
        guard !task.isEmpty, ProjectMatch.exact(task, in: projects) == nil else { return nil }
        return ProjectMatch.similar(to: task, in: projects, limit: 1).first
    }

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

}
