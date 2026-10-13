import SwiftUI

@main
struct FocusCompanionApp: App {
    @State private var model: AppModel

    /// Launch flags for screenshots and demos: `-demo` starts against the pretend Mac, `-demo-session` also starts a session,
    /// and `-tab insights|mac` opens that tab.
    init() {
        let args = ProcessInfo.processInfo.arguments
        let m = AppModel(demo: args.contains("-demo") || args.contains("-demo-session"))
        if args.contains("-demo-session") { m.start(task: "Calc homework", minutes: 25) }
        _model = State(initialValue: m)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.accent)
        }
    }
}
