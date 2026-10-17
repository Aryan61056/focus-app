import AppKit
import FocusUI
import FocusSense

/// Takes you to the window, tab or document you were working in. In a browser the tab is chosen with AppleScript (by address, then by title)
/// before the browser comes forward; anywhere else the matching window is raised with Accessibility. If neither finds it, the app comes forward
/// and the answer says so ("appOnly"), so the controller never claims more than it did. Runs on the main thread; each script is capped at 3 seconds.
@MainActor enum Place {
    static func go(to w: WindowSnapshot, allowTabs: Bool) -> ReturnOutcome {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == w.app && $0.activationPolicy == .regular && !$0.isTerminated }) else { return .notFound }
        var exact = false
        if allowTabs, Enforcement.isBrowser(w.app) {
            if !w.url.isEmpty { exact = Tabs.run(TabScript.switchTo(app: w.app, url: w.url)) == "ok" }
            if !exact, !w.title.isEmpty { exact = Tabs.run(TabScript.switchToTitle(app: w.app, title: w.title)) == "ok" }
        }
        if !exact { exact = WindowRaiser.raise(pid: app.processIdentifier, matching: w) }
        if app.isHidden { app.unhide() }
        WindowRaiser.bringForward(pid: app.processIdentifier)
        app.activate()
        return exact ? .exact : .appOnly
    }
}
