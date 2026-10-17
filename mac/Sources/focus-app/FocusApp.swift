import SwiftUI
import FocusUI
import FocusJudge
import FocusSense
import FocusLink
import FocusSocial
import CloudKit
import AppKit
import AVFoundation

@main
struct FocusApp: App {
    // FOCUS_DEMO=1 runs a scripted session against an in-memory store, so demo data never reaches the real store file.
    @State private var controller = ProcessInfo.processInfo.environment["FOCUS_DEMO"] == "1"
        ? SessionController(judge: ScriptedJudge(markers: [("youtube", .off), ("Calc", .on), ("khanacademy", .on)]), store: DataStore(),
                            prefs: Preferences(defaults: Self.demoDefaults()))
        : Self.makeController()
    /// Demo settings live in their own suite, wiped at each launch, so a demo run never changes the real app's settings.
    static func demoDefaults() -> UserDefaults {
        let name = "focus-app.demo"
        UserDefaults.standard.removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }
    /// FOCUS_TEST_STORE=<folder> keeps the real judge and real sensing but uses a throwaway store and settings,
    /// so testing never adds sessions to the owner's history.
    static func makeController() -> SessionController {
        if let dir = ProcessInfo.processInfo.environment["FOCUS_TEST_STORE"], !dir.isEmpty {
            let folder = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let defaults = UserDefaults(suiteName: "focus-app.test.\(folder.lastPathComponent)") ?? .standard
            return SessionController(judge: DefaultJudge.make(), store: DataStore(url: folder.appendingPathComponent("store.json")), prefs: Preferences(defaults: defaults))
        }
        let store = DataStore(url: DataStore.defaultURL)
        // Once: remove the one-project-per-keystroke leftovers an earlier build made while a name was typed (a copy of the file is kept).
        if !UserDefaults.standard.bool(forKey: "cleanedTypingLeftovers.1") { store.removeTypingLeftovers(); UserDefaults.standard.set(true, forKey: "cleanedTypingLeftovers.1") }
        return SessionController(judge: DefaultJudge.make(), store: store, prefs: Preferences())
    }
    /// With two displays the pause screen would otherwise appear on whichever one the window was last on, not where you are looking.
    static func bringToPointerScreen() {
        guard let here = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }),
              let w = NSApp.windows.first(where: { $0.title == "Focus" && $0.canBecomeMain && $0.isVisible }),
              let now = w.screen, now != here else { return }
        var f = w.frame
        f.origin = NSPoint(x: here.visibleFrame.midX - f.width / 2, y: here.visibleFrame.midY - f.height / 2)
        w.setFrame(f, display: true)
    }
    @State private var demo: DemoSenses?
    @State private var notch: NotchPanelController?
    @State private var sense: SenseCoordinator?
    @State private var previewWatcher: PreviewWatcher?
    @State private var hotKey = GlobalHotKey()
    @State private var updater: Updater?

    init() {
        // Focus lives in the menu bar and the notch and watches a session with its window closed, so macOS must never quit it
        // for having no window on screen (automatic termination quit it about 25 s after the window was hidden).
        ProcessInfo.processInfo.disableAutomaticTermination("Focus watches your session from the menu bar and the notch.")
    }
    @State private var veil: VeilController?
    @State private var banner: BannerController?
    @State private var shield: ShieldController?
    @State private var cueClock: CueClock?
    @State private var voice = Voice()
    @State private var phoneLink = PhoneLink()
    @NSApplicationDelegateAdaptor(FocusAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    /// Friends (docs/SOCIAL.md). The demo gets made-up friends and never touches iCloud; FOCUS_DEMO_FRIENDS=1 turns sharing on in it.
    /// A throwaway store (FOCUS_TEST_STORE) keeps no local copy of friends.
    func setUpFriends() {
        let env = ProcessInfo.processInfo.environment
        if env["FOCUS_DEMO"] == "1" {
            let f = FriendsStore(transport: DemoFriendsTransport.sample(), prefs: controller.prefs, store: controller.store)
            controller.friends = f
            if env["FOCUS_DEMO_FRIENDS"] == "1" { controller.prefs.friendName = "Ari"; controller.prefs.friendEmoji = "\u{1F43C}"; Task { await f.setSharing(true) } }
            return
        }
        let ck = CloudKitFriends()
        let f = FriendsStore(transport: ck, prefs: controller.prefs, store: controller.store,
                             url: (env["FOCUS_TEST_STORE"] ?? "").isEmpty ? FriendsStore.defaultURL : nil)
        controller.friends = f
        // A friend's invite link opened this app: join their board, then show it.
        FocusAppDelegate.onAcceptShare = { metadata in
            Task { @MainActor in
                do { try await ck.accept(metadata) } catch { return }
                controller.requestSection(.friends)
                await f.refresh()
            }
        }
        FocusAppDelegate.onRemoteNotification = { info in Task { @MainActor in ck.receive(info) } }
        if f.sharing { Task { await f.refresh() } }
    }

    var body: some Scene {
        Window("Focus", id: "main") {
            RootView(controller: controller)
                .task {
                    // Real window sensing, except in the scripted demo. It only runs while a session is active.
                    if sense == nil, ProcessInfo.processInfo.environment["FOCUS_DEMO"] != "1" {
                        controller.onOpenAccessSettings = {
                            AXWindowSource.promptForAccess()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                        }
                        let addr = BrowserAddressSource(enabled: { controller.prefs.switchTabs || controller.prefs.closeOnStrict })
                        controller.senseNow = { addr.current() }
                        let sc = SenseCoordinator(source: BrowserAddressSource(enabled: { controller.prefs.switchTabs || controller.prefs.closeOnStrict }), controller: controller); sense = sc; sc.bind()
                        let pw = PreviewWatcher(grabber: SCKScreenGrabber(), controller: controller) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
                        }
                        previewWatcher = pw; pw.bind()
                    }
                    // One soft system tone, only when the user turned nudge sound on (the brain emits the cue only then).
                    controller.onCue = { NSSound(named: "Tink")?.play() }
                    // The ladder: bring the Focus window (the pause screen) forward on the pointer's screen, and hide the app you drifted into.
                    // Hiding is the same as Command-H: nothing is closed and no work is lost.
                    controller.onForeground = { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main"); Self.bringToPointerScreen() }
                    controller.onHideApp = { name in
                        NSWorkspace.shared.runningApplications.first { $0.localizedName == name && $0.activationPolicy == .regular && $0 != NSRunningApplication.current }?.hide()
                    }
                    controller.onSwitchTab = { from, to in Tabs.switchAway(from: from, to: to) }
                    controller.onCloseTab = { Tabs.close($0) }
                    if veil == nil { let v = VeilController(controller: controller); veil = v; v.start() }
                    // The quieter cues. Each one is silent except the voice, which is off until the user turns it on. The controller decides when.
                    controller.frontWindowFrame = { AXWindowSource.frontWindowFrame() }
                    if banner == nil { let b = BannerController(controller: controller); banner = b; b.start() }
                    if shield == nil { let f = ShieldController(controller: controller); shield = f; f.start() }
                    if cueClock == nil { let k = CueClock(controller: controller); cueClock = k; k.start() }
                    controller.onHaptic = { Haptics.play($0) }
                    controller.onSpeak = { voice.say($0) }
                    controller.onDockBounce = { if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) } }
                    // The iPhone link stays off until turned on in Session > iPhone, and never runs in the scripted demo.
                    if ProcessInfo.processInfo.environment["FOCUS_DEMO"] != "1" { phoneLink.attach(controller) }
                    controller.onBringBackToApp = { name in
                        NSWorkspace.shared.runningApplications.first { $0.localizedName == name && $0.activationPolicy == .regular }?.activate()
                    }
                    // Quitting during a session ends it, so the session is saved instead of vanishing.
                    NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                        MainActor.assumeIsolated { if controller.isActive { controller.end() } }
                    }
                    controller.onOpenModelSettings = {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                    if controller.friends == nil { setUpFriends() }
                    if updater == nil, ProcessInfo.processInfo.environment["FOCUS_DEMO"] != "1" { let u = Updater(controller: controller); updater = u; u.start() }
                    controller.setJudgeStatus(DefaultJudge.status())
                    Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in MainActor.assumeIsolated { controller.setJudgeStatus(DefaultJudge.status()) } }
                    hotKey.register {
                        if controller.isActive { controller.act(controller.isPaused ? .resume : .pause) }
                        else { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main"); controller.requestStart() }
                    }
                    if notch == nil { let n = NotchPanelController(controller: controller); notch = n; n.start() }
                    // FOCUS_DEMO_NOTCH="peek@4,open@6,peek@9,rest@11" drives the notch on a timeline (demo only), so its motion can be
                    // recorded frame by frame without moving the real pointer.
                    if ProcessInfo.processInfo.environment["FOCUS_DEMO"] == "1", let script = ProcessInfo.processInfo.environment["FOCUS_DEMO_NOTCH"], let n = notch {
                        for step in script.split(separator: ",") {
                            let parts = step.split(separator: "@"); guard parts.count == 2, let at = Double(parts[1]) else { continue }
                            let what = String(parts[0])
                            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                                switch what {
                                case "drop": n.setHoverForTesting(true); n.setDropTargetedForTesting(true)
                                case "landed":
                                    n.setDropTargetedForTesting(false); n.setExpandedForTesting(true)
                                    // FOCUS_DEMO_TRAY: a list of files (made for the demo, never the user's) to put on the shelf.
                                    let paths = (ProcessInfo.processInfo.environment["FOCUS_DEMO_TRAY"] ?? "").split(separator: ":").map(String.init)
                                    NotchTray.shared.add(paths.map { URL(fileURLWithPath: $0) })
                                case "peek": n.setExpandedForTesting(false); n.setHoverForTesting(true)
                                case "open": n.setHoverForTesting(true); n.setExpandedForTesting(true)
                                case "tray", "widgets", "home": n.setTabForTesting(NotchTab(rawValue: what) ?? .home)
                                default: n.setExpandedForTesting(false); n.setHoverForTesting(false)
                                }
                            }
                        }
                    }
                    guard ProcessInfo.processInfo.environment["FOCUS_DEMO"] == "1", demo == nil else { return }
                    let d = DemoSenses(controller: controller, script: [
                        .init(after: 0.5, window: WindowSnapshot(app: "Notes", title: "Calc homework")),
                        .init(after: 20, window: WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1")),
                        .init(after: 150, window: WindowSnapshot(app: "Notes", title: "Calc homework")),
                    ])
                    demo = d
                    // The demo's store is empty, so a demo would open on the welcome; FOCUS_DEMO_WELCOME=1 asks for it.
                    if ProcessInfo.processInfo.environment["FOCUS_DEMO_WELCOME"] != "1" { controller.prefs.welcomeSeen = true }
                    SampleData.seedIfRequested(controller.store); DemoPreview.startIfRequested(controller)
                    SelfShot.scheduleIfRequested(); SelfShot.runActions(controller)
                    // FOCUS_DEMO_NOSESSION=1 leaves the app idle so the start flow can be driven (tools and screenshots).
                    if ProcessInfo.processInfo.environment["FOCUS_DEMO_NOSESSION"] == "1" { return }
                    controller.begin(task: "Calc homework", preset: ProcessInfo.processInfo.environment["FOCUS_DEMO_STRICT"] == "1" ? .strict : .standard, shadow: false, autoTick: true)
                    d.start()
                }
        }
        .defaultSize(width: 1240, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Session") {
                Button("Start session\u{2026}") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main"); controller.requestStart() }
                    .keyboardShortcut("n").disabled(controller.isActive)
                Button(controller.isPaused ? "Resume" : "Pause") { controller.act(controller.isPaused ? .resume : .pause) }
                    .keyboardShortcut("p", modifiers: [.command, .shift]).disabled(!controller.isActive)
                Button("End session") { controller.end() }
                    .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(!controller.isActive)
                Divider()
                Button("iPhone\u{2026}") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "iphone") }
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.rawValue) { controller.requestSection(s) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                        .disabled(s == .review && !controller.showsReview)
                }
            }
        }

        Window("iPhone", id: "iphone") { PhoneLinkView(link: phoneLink) }
            .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent(controller: controller) {
                // The window-style popover stays open after a click, so close it before showing the app.
                NSApp.windows.filter { String(describing: type(of: $0)).contains("MenuBarExtra") }.forEach { $0.orderOut(nil) }
                NSApp.activate(ignoringOtherApps: true); openWindow(id: "main")
            }
        } label: {
            MenuBarLabel(controller: controller, clock: cueClock ?? CueClock(controller: controller))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Only here for iCloud: macOS hands an accepted invite and remote notifications to the app delegate, which SwiftUI has no other way to receive.
final class FocusAppDelegate: NSObject, NSApplicationDelegate {
    /// An invite opened before the window set Friends up is kept and handed over when it does.
    nonisolated(unsafe) static var pendingShares: [CKShare.Metadata] = []
    nonisolated(unsafe) static var onAcceptShare: ((CKShare.Metadata) -> Void)? {
        didSet { if let f = onAcceptShare { pendingShares.forEach(f); pendingShares = [] } }
    }
    nonisolated(unsafe) static var onRemoteNotification: (([String: Any]) -> Void)?

    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        if let f = Self.onAcceptShare { f(metadata) } else { Self.pendingShares.append(metadata) }
    }
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Self.onRemoteNotification?(userInfo)
    }
}
