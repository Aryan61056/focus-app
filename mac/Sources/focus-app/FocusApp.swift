import SwiftUI
import FocusUI
import FocusJudge

@main
struct FocusApp: App {
    @State private var controller = SessionController(judge: ProcessInfo.processInfo.environment["FOCUS_DEMO"] == "1"
        ? ScriptedJudge(markers: [("youtube", .off), ("Calc", .on), ("khanacademy", .on)])
        : DefaultJudge.make())
    @State private var demo: DemoSenses?
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Focus", id: "main") {
            RootView(controller: controller)
                .task {
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
