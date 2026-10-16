import AppKit
import FocusUI

/// Developer tool, only with FOCUS_DEMO=1 and FOCUS_SELFSHOT=<folder>: after a few seconds, draws this app's own windows (the main window
/// and the notch panel, with scripted demo data) to PNG files and quits. It renders views, it does not capture the screen, so it needs no permission.
@MainActor
enum SelfShot {
    /// FOCUS_DEMO_ACTIONS="section:settings,start" runs these on the controller after 3 s (demo only), in place of clicks and keys I cannot send:
    /// section:<today|projects|history|insights|review|settings>, page:<settings page>, text:<1 to 1.5>, start (opens the start sheet), readscreen (turns screen reading on), veil (the whole-screen gray fade, 10 s).
    static func runActions(_ controller: SessionController) {
        let env = ProcessInfo.processInfo.environment
        guard env["FOCUS_DEMO"] == "1", let list = env["FOCUS_DEMO_ACTIONS"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            for a in list.split(separator: ",").map(String.init) {
                if a.hasPrefix("section:"), let s = AppSection.allCases.first(where: { $0.rawValue.lowercased() == a.dropFirst(8).lowercased() }) { controller.requestSection(s) }
                else if a.hasPrefix("page:"), let p = SettingsPage.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(a.dropFirst(5).lowercased()) }) { controller.requestSettingsPage(p) }
                else if a == "start" { controller.requestStart() }
                else if a == "readscreen" { controller.prefs.readScreen = true }
                else if a.hasPrefix("text:"), let f = Double(a.dropFirst(5)) { controller.prefs.textScale = f }   // text:1.5, the Text size setting
                else if a == "veil" { controller.previewVeil() }   // the whole-screen gray, so its windows can be listed
            }
        }
    }

    static func scheduleIfRequested(after seconds: Double = 12) {
        let env = ProcessInfo.processInfo.environment
        guard env["FOCUS_DEMO"] == "1", let dir = env["FOCUS_SELFSHOT"] else { return }
        // FOCUS_SELFSHOT_APPEARANCE=light|dark renders in that appearance whatever the system uses.
        if let a = env["FOCUS_SELFSHOT_APPEARANCE"] { NSApp.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua) }
        // FOCUS_SELFSHOT_SIZE=960x600 resizes the main window first, so the smallest and a large window can both be checked.
        if let s = env["FOCUS_SELFSHOT_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), s.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                for w in NSApp.windows where w.canBecomeMain && w.sheetParent == nil && w.isVisible { w.setContentSize(NSSize(width: s[0], height: s[1])) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(env["FOCUS_SELFSHOT_AFTER"] ?? "") ?? seconds)) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            for (i, w) in NSApp.windows.enumerated() where w.isVisible {
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
                    if let img = ownWindowImage(CGWindowID(x.windowNumber)), let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
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
