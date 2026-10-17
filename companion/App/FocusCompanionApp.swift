import SwiftUI
import UIKit

@main
struct FocusCompanionApp: App {
    @State private var model: AppModel
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate

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

/// Only here for iCloud: a push says the Mac wrote new Insights, and UIKit hands those to the app delegate, not to SwiftUI.
final class PushDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await MainActor.run { AppModel.shared.cloud.receive(userInfo) } ? .newData : .noData
    }
}
