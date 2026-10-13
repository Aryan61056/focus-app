import AppKit
import FocusUI

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
