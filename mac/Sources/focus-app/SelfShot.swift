import AppKit
import SwiftUI
import FocusUI
import FocusJudge

/// Developer tool, only with FOCUS_DEMO=1 and FOCUS_SELFSHOT=<folder>: after a few seconds, draws this app's own windows (the main window
/// and the notch panel, with scripted demo data) to PNG files and quits. It renders views, it does not capture the screen, so it needs no permission.
@MainActor
enum SelfShot {
    /// FOCUS_DEMO_ACTIONS="section:settings,start" runs these on the controller after 3 s (demo only), in place of clicks and keys I cannot send:
    /// section:<today|projects|history|insights|review|settings>, page:<settings page>, text:<1 to 1.5>, pause, nonotch, sidebar (shows or hides it, as the toolbar button does), hide, start (opens the start sheet), readscreen (turns screen reading on), veil (the whole-screen gray fade, 10 s), nogray (no whole-screen gray).
    static func runActions(_ controller: SessionController) {
        let env = ProcessInfo.processInfo.environment
        guard env["FOCUS_DEMO"] == "1", let list = env["FOCUS_DEMO_ACTIONS"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            for a in list.split(separator: ",").map(String.init) {
                if a.hasPrefix("section:"), let s = AppSection.allCases.first(where: { $0.rawValue.lowercased() == a.dropFirst(8).lowercased() }) { controller.requestSection(s) }
                else if a.hasPrefix("page:"), let p = SettingsPage.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(a.dropFirst(5).lowercased()) }) { controller.requestSettingsPage(p) }
                else if a.hasPrefix("example") {
                    controller.showExample()
                    let parts = a.split(separator: ":")
                    if parts.count == 2, let step = Int(parts[1]) { controller.example?.select(step) }
                }
                else if a == "stuck" { controller.assistant = ExampleAssistant(); controller.requestNextActions() }
                else if a == "park" || a == "park-long" { controller.onParkThought?() }
                else if a == "parked-all" {
                    for i in 1...12 { controller.store?.park("Synthetic thought \(i): ask about the lab materials") }
                    controller.act(.breakTime, minutes: 5)
                }
                else if a == "parked" { controller.store?.park("Ask about the synthetic lab materials"); controller.store?.park("Pick up a notebook"); controller.act(.breakTime, minutes: 5) }
                else if a == "start-until" {
                    controller.startDraft.task = "Lab report"; controller.startDraft.length = .until
                    controller.startDraft.done = "Write the methods section"; controller.startDraft.extras = true; controller.requestStart()
                }
                else if a == "goal-finished" {
                    if controller.isActive { controller.end() }
                    controller.begin(task: "Lab report", goal: "Write the methods section"); controller.end()
                }
                else if a == "start" { controller.requestStart() }
                else if a == "readscreen" { controller.prefs.readScreen = true }
                else if a == "pause" { controller.act(.pause) }   // the held state: nothing is read until resume
                else if a.hasPrefix("text:"), let f = Double(a.dropFirst(5)) { controller.prefs.textScale = f }   // text:1.5, the Text size setting
                else if a == "sidebar", let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.sheetParent == nil }),
                        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .command], timestamp: 0, windowNumber: w.windowNumber,
                                                 context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1) { _ = w.performKeyEquivalent(with: e) }   // the sidebar button's own shortcut
                else if a == "hide" { NSApp.hide(nil) }   // the window out of sight, as during most of a session
                else if a == "nonotch" { controller.prefs.showNotch = false }   // for measuring what the notch costs
                else if a == "veil" { controller.previewVeil() }   // the whole-screen gray, so its windows can be listed
                else if a == "nogray" { controller.prefs.screenGrayscale = false }
                else if a == "offline", let f = controller.friends { f.demoTransport?.offline = true; Task { await f.refresh() } }   // the "could not update" notice
                else if a.hasPrefix("board:") { controller.friends?.board = Scoreboard.Board.allCases.first { "\($0)" == a.dropFirst(6) } ?? .focused }   // board:steady   // keep the real display in color while panels are checked
            }
        }
    }

    /// The main window drops to a level under the desktop picture, so it is never seen on any display but is still a real window the
    /// window server can copy; the notch panel and menu bar item go fully transparent. Windows that appear later (a sheet follows its
    /// parent) are caught by the timer that calls this.
    static func keepQuiet() {
        for w in NSApp.windows where w.sheetParent == nil {
            w.ignoresMouseEvents = true
            if w is NSPanel || !w.canBecomeMain { w.alphaValue = 0 }
            else { w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1) }
        }
    }

    /// FOCUS_DEMO_MENU=1 (demo only) shows the menu bar popover's content in an ordinary window, since a status item cannot be clicked from here.
    static func showMenuIfRequested(_ controller: SessionController) {
        guard ProcessInfo.processInfo.environment["FOCUS_DEMO"] == "1", ProcessInfo.processInfo.environment["FOCUS_DEMO_MENU"] == "1" else { return }
        let host = NSHostingController(rootView: MenuBarContent(controller: controller) {}.background(Color(nsColor: .windowBackgroundColor)))
        let w = NSWindow(contentViewController: host)
        w.title = "Menu"; w.styleMask = [.titled]; w.setFrameOrigin(NSPoint(x: 80, y: 120)); w.makeKeyAndOrderFront(nil)
    }

    static func scheduleIfRequested(after seconds: Double = 12) {
        let env = ProcessInfo.processInfo.environment
        guard env["FOCUS_DEMO"] == "1", let dir = env["FOCUS_SELFSHOT"] else { return }
        // FOCUS_SELFSHOT_APPEARANCE=light|dark renders in that appearance whatever the system uses.
        if let a = env["FOCUS_SELFSHOT_APPEARANCE"] { NSApp.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua) }
        // FOCUS_SELFSHOT_QUIET=1 puts the main window under the desktop picture and makes the rest transparent and deaf to the pointer for the whole run,
        // so a render never shows anything on the screen or takes a click. Launch it with `open -g` so it does not take focus either.
        if env["FOCUS_SELFSHOT_QUIET"] == "1" {
            keepQuiet()
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in MainActor.assumeIsolated { SelfShot.keepQuiet() } }
        }
        // FOCUS_SELFSHOT_SIZE=960x600 resizes the main window first, so the smallest and a large window can both be checked.
        if let s = env["FOCUS_SELFSHOT_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), s.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                for w in NSApp.windows where w.canBecomeMain && w.sheetParent == nil && w.isVisible { w.setContentSize(NSSize(width: s[0], height: s[1])) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(env["FOCUS_SELFSHOT_AFTER"] ?? "") ?? seconds)) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            // What was there, so a missing image can be told from a window that was not on screen.
            let listing = NSApp.windows.enumerated().map { i, w in
                "\(i) \(type(of: w)) visible=\(w.isVisible) canHide=\(w.canHide) number=\(w.windowNumber) occluded=\(!w.occlusionState.contains(.visible)) frame=\(Int(w.frame.width))x\(Int(w.frame.height)) at \(Int(w.frame.origin.x)),\(Int(w.frame.origin.y))"
            }.joined(separator: "\n")
            try? listing.write(toFile: "\(dir)/windows.txt", atomically: true, encoding: .utf8)
            // While the app is hidden AppKit reports every window as not visible, even the panels that stay on screen (canHide off).
            for (i, w) in NSApp.windows.enumerated() where w.isVisible || (!w.canHide && w.windowNumber > 0 && w.occlusionState.contains(.visible)) {
                // A focused text field's editor keeps the views around it from drawing offscreen, so drop focus first.
                w.makeFirstResponder(nil); w.contentView?.layoutSubtreeIfNeeded(); w.displayIfNeeded()
                guard let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(dir)/window-\(i)-\(Int(w.frame.width))x\(Int(w.frame.height)).png"))
                }
                // The window server's copy of this app's own window: draws glass, text fields and sheets that cacheDisplay skips.
                // Only this process's windows; no other window or screen content is read.
                for (j, x) in ([w] + (w.attachedSheet.map { [$0] } ?? [])).enumerated() {
                    // Status item windows report numbers that are not window IDs (negative, or 2^32 and up); converting one trapped and
                    // ended the render before it reached the notch and banner panels.
                    guard let id = CGWindowID(exactly: x.windowNumber), id > 0 else { continue }
                    if let img = ownWindowImage(id), let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: "\(dir)/server-\(i)\(j == 0 ? "" : "-sheet")-\(Int(x.frame.width))x\(Int(x.frame.height)).png"))
                    }
                }
            }
            NSApp.terminate(nil)
            // An open sheet can keep terminate from finishing; this is a dev tool, so leave regardless.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
        }
    }

    /// CGWindowListCreateImage for one window of this process. Deprecated, so it is looked up at run time; nil if it is gone.
    static func ownWindowImage(_ id: CGWindowID) -> CGImage? {
        typealias Fn = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?
        guard let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "CGWindowListCreateImage") else { return nil }
        let f = unsafeBitCast(sym, to: Fn.self)
        // .null rect = the window's bounds; optionIncludingWindow = 1 << 3; boundsIgnoreFraming = 1 << 0, bestResolution = 1 << 3.
        return f(.null, 1 << 3, id, (1 << 0) | (1 << 3))?.takeRetainedValue()
    }
}

private struct ExampleAssistant: Assistant {
    func sharpen(task: String, context: String) async -> Sharpened? { nil }
    func recap(facts: String) async -> Recap? { nil }
    func answer(question: String, facts: String) async -> String? { nil }
    func nextActions(task: String, context: String) async -> [String]? {
        ["Choose u and dv for the first calculus integral.", "Differentiate your chosen calculus expression.", "Write the calculus rule beside your working."]
    }
}
