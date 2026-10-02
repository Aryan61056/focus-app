import SwiftUI
import FocusUI
import FocusJudge

@main
struct FocusApp: App {
    // FOCUS_DEMO=1 runs a scripted session against an in-memory store, so demo data never reaches the real store file.
    @State private var controller = ProcessInfo.processInfo.environment["FOCUS_DEMO"] == "1"
        ? SessionController(judge: ScriptedJudge(markers: [("youtube", .off), ("Calc", .on), ("khanacademy", .on)]), store: DataStore())
        : SessionController(judge: DefaultJudge.make(), store: DataStore(url: DataStore.defaultURL), prefs: Preferences())
    @State private var demo: DemoSenses?
    @State private var notch: NotchPanelController?
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Focus", id: "main") {
            RootView(controller: controller)
                .task {
                    if notch == nil { let n = NotchPanelController(controller: controller) { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }; notch = n; n.start() }
                    guard ProcessInfo.processInfo.environment["FOCUS_DEMO"] == "1", demo == nil else { return }
                    let d = DemoSenses(controller: controller, script: [
                        .init(after: 0.5, window: WindowSnapshot(app: "Notes", title: "Calc homework")),
                        .init(after: 20, window: WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1")),
                        .init(after: 150, window: WindowSnapshot(app: "Notes", title: "Calc homework")),
                    ])
                    demo = d
                    controller.begin(task: "Calc homework", preset: .standard, shadow: false, autoTick: true)
                    d.start()
                }
        }
        .defaultSize(width: 1240, height: 800)

        MenuBarExtra {
            MenuBarContent(controller: controller) { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
        } label: {
            Image(nsImage: RingImage.make(controller.ringState))
        }
        .menuBarExtraStyle(.window)
    }
}
