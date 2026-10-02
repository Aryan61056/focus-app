import SwiftUI
import FocusUI
import FocusJudge
import FocusSense
import AppKit

@main
struct FocusApp: App {
    // FOCUS_DEMO=1 runs a scripted session against an in-memory store, so demo data never reaches the real store file.
    @State private var controller = ProcessInfo.processInfo.environment["FOCUS_DEMO"] == "1"
        ? SessionController(judge: ScriptedJudge(markers: [("youtube", .off), ("Calc", .on), ("khanacademy", .on)]), store: DataStore())
        : SessionController(judge: DefaultJudge.make(), store: DataStore(url: DataStore.defaultURL), prefs: Preferences())
    @State private var demo: DemoSenses?
    @State private var notch: NotchPanelController?
    @State private var sense: SenseCoordinator?
    @State private var previewWatcher: PreviewWatcher?
    @State private var hotKey = GlobalHotKey()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Focus", id: "main") {
            RootView(controller: controller)
                .onChange(of: controller.surface) { _, s in
                    // The strict pause screen lives in this window, so it has to come forward to be seen.
                    if s?.kind == "gate" { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
                }
                .task {
                    // Real window sensing, except in the scripted demo. It only runs while a session is active.
                    if sense == nil, ProcessInfo.processInfo.environment["FOCUS_DEMO"] != "1" {
                        controller.onOpenAccessSettings = {
                            AXWindowSource.promptForAccess()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                        }
                        controller.senseNow = { AXWindowSource().current() }
                        let sc = SenseCoordinator(source: AXWindowSource(), controller: controller); sense = sc; sc.bind()
                        let pw = PreviewWatcher(grabber: SCKScreenGrabber(), controller: controller) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
                        }
                        previewWatcher = pw; pw.bind()
                    }
                    controller.onBringBackToApp = { name in
                        NSWorkspace.shared.runningApplications.first { $0.localizedName == name && $0.activationPolicy == .regular }?.activate()
                    }
                    hotKey.register {
                        if controller.isActive { controller.act(controller.isPaused ? .resume : .pause) }
                        else { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main"); controller.requestStart() }
                    }
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
        .commands {
            CommandMenu("Session") {
                Button("Start session\u{2026}") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main"); controller.requestStart() }
                    .keyboardShortcut("n").disabled(controller.isActive)
                Button(controller.isPaused ? "Resume" : "Pause") { controller.act(controller.isPaused ? .resume : .pause) }
                    .keyboardShortcut("p", modifiers: [.command, .shift]).disabled(!controller.isActive)
                Button("End session") { controller.end() }
                    .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(!controller.isActive)
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.rawValue) { controller.requestSection(s) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
        }

        MenuBarExtra {
            MenuBarContent(controller: controller) { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
        } label: {
            Image(nsImage: RingImage.make(controller.ringState))
        }
        .menuBarExtraStyle(.window)
    }
}
