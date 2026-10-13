import AppKit
import FocusUI
import FocusSense

/// Steers a browser tab with AppleScript. The first run asks the user for Automation permission for that browser; if it is refused or
/// the browser is slow, the call returns false and the ladder hides the app instead. Runs on the main thread, capped at 3 seconds.
@MainActor enum Tabs {
    private static func run(_ source: String?) -> String? {
        guard let source, let script = NSAppleScript(source: source) else { return nil }
        var err: NSDictionary?
        let out = script.executeAndReturnError(&err)
        return err == nil ? out.stringValue : nil
    }

    /// Brings the tab you were last working in forward. False when there is none to go to.
    static func switchAway(from w: WindowSnapshot, to onTask: WindowSnapshot?) -> Bool {
        guard let t = onTask, t.app == w.app, !t.url.isEmpty else { return false }
        return run(TabScript.switchTo(app: t.app, url: t.url)) == "ok"
    }

    static func close(_ w: WindowSnapshot) -> Bool { run(TabScript.close(app: w.app, url: w.url)) == "ok" }
}

/// Chrome, Brave and Edge do not report the page address through Accessibility, so without it Focus could not tell one tab from another
/// (every Chrome tab looked like the same "site", and no tab could be switched to or closed). This asks the browser for the front tab's
/// address with AppleScript, only while a session runs and only when a tab feature is on. Private windows return nothing.
/// If the user refuses the permission it stops asking for a minute.
@MainActor final class BrowserAddressSource: @MainActor WindowSource {
    private let inner = AXWindowSource()
    private let enabled: () -> Bool
    private var cache: (app: String, title: String, url: String, at: Date)?
    private var pausedUntil = Date.distantPast
    init(enabled: @escaping () -> Bool) { self.enabled = enabled }

    var isTrusted: Bool { inner.isTrusted }

    func current() -> WindowSnapshot? {
        guard var w = inner.current() else { return nil }
        guard w.url.isEmpty, enabled(), Enforcement.isBrowser(w.app), let source = TabScript.currentURL(app: w.app), Date() >= pausedUntil else { return w }
        if let c = cache, c.app == w.app, c.title == w.title, Date().timeIntervalSince(c.at) < 4 { w.url = c.url; return w }
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return w }
        let out = script.executeAndReturnError(&err)
        if err != nil { pausedUntil = Date().addingTimeInterval(60); return w }
        let url = out.stringValue ?? ""
        cache = (w.app, w.title, url, Date())
        w.url = url
        return w
    }
}
