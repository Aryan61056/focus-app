import SwiftUI
import FocusBrain

public struct StartSheet: View {
    @Bindable var c: SessionController
    @Binding var isPresented: Bool
    public init(controller: SessionController, isPresented: Binding<Bool>) { c = controller; _isPresented = isPresented }
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StartForm(c: c) { isPresented = false }
            HStack { Spacer(); Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 520).onExitCommand { isPresented = false }
    }
    static func lastProject(_ store: DataStore?) -> Project? {
        guard let store, let r = store.sessions.max(by: { $0.start < $1.start }) else { return nil }
        return store.project(r.projectId)
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
