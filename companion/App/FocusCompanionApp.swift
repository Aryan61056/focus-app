import SwiftUI

@main
struct FocusCompanionApp: App {
    @State private var model: AppModel

    /// Launch flags for screenshots and demos: `-demo` starts against the pretend Mac, `-demo-session` also starts a session,
    /// and `-tab insights|mac` opens that tab.
    init() {
        let args = ProcessInfo.processInfo.arguments
        let demoFlags = args.contains("-demo") || args.contains("-demo-session")
        let m = demoFlags ? AppModel(demo: true) : AppModel.shared
        if args.contains("-demo-session") { m.start(task: "Calc homework", minutes: 25) }
        #if DEBUG
        if args.contains("-show-guard") { m.showGuard() }
        if let i = args.firstIndex(of: "-pair"), i + 1 < args.count { m.autoPair(code: args[i + 1]) }
        if let i = args.firstIndex(of: "-remote-start"), i + 1 < args.count { m.autoStart(task: args[i + 1]) }
        #endif
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
