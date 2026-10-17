import AppKit
import FocusUI
import FocusSense

/// Takes you to the window, tab or document you were working in. In a browser the tab is chosen with AppleScript (by address, then by
/// title); anywhere else the matching window is raised with Accessibility, and failing that the matching tab in the app's tab bar is pressed
/// (a terminal, a Finder window, Firefox, a document app). If the place is gone (the document closed, the tab shut, the app quit) and you
/// pressed Back to task, it is opened again. If none of that finds it, the app comes forward and the answer says so ("appOnly"), so the
/// controller never claims more than it did. Runs on the main thread; each script is capped at 3 seconds.
@MainActor enum Place {
    static func go(to w: WindowSnapshot, allowTabs: Bool, reopen: Bool) -> ReturnOutcome {
        guard let app = running(w.app) else {
            // The app quit. Start it with the document or page, if there is one to open.
            return reopen && open(w, in: nil) ? .reopened : .notFound
        }
        var exact = false, pageIsGone = false
        if allowTabs, Enforcement.isBrowser(w.app) {
            var urlSaidNone = false, titleSaidNone = true   // no title to try is as good as "none"
            if !w.url.isEmpty { let r = Tabs.run(TabScript.switchTo(app: w.app, url: w.url, space: w.space)); exact = r == "ok"; urlSaidNone = r == "none" }
            if !exact, !w.title.isEmpty, let script = TabScript.switchToTitle(app: w.app, title: w.title, space: w.space) {
                let r = Tabs.run(script); exact = r == "ok"; titleSaidNone = r == "none"
            }
            // Only a definite "no such tab" lets the page be opened again; a refused permission or a slow browser is not "gone".
            pageIsGone = !exact && urlSaidNone && titleSaidNone
        }
        if !exact { exact = WindowRaiser.raise(pid: app.processIdentifier, matching: w) }
        // The app's own tab bar, when no script reached the tab (Automation refused, or an app with no scripting).
        if !exact, allowTabs { exact = WindowRaiser.raiseTab(pid: app.processIdentifier, matching: w) }
        var reopened = false
        if !exact, reopen {
            // A document that is already open just comes forward when opened again, so this is safe even if the window was merely not matched.
            if !w.documentPath.isEmpty { reopened = open(w, in: app) } else if pageIsGone { reopened = open(w, in: app) }
        }
        if app.isHidden { app.unhide() }
        WindowRaiser.bringForward(pid: app.processIdentifier)
        app.activate()
        return exact ? .exact : (reopened ? .reopened : .appOnly)
    }

    /// Where the place's window is on screen, for the beacon ring.
    static func frame(of w: WindowSnapshot) -> CGRect? {
        guard let app = running(w.app) else { return nil }
        // When the app is the one in front, "its only window" is the window you are in, not the place you drifted from: outline nothing then.
        let inFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        return WindowRaiser.frame(pid: app.processIdentifier, matching: w, allowOnlyWindow: !inFront)
    }

    private static func running(_ name: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.localizedName == name && $0.activationPolicy == .regular && !$0.isTerminated }
    }

    /// Opens the document, folder or page of `w` in its app, starting the app if it has quit. Only things ReopenPolicy allows.
    private static func open(_ w: WindowSnapshot, in app: NSRunningApplication?) -> Bool {
        let target: URL
        if !w.documentPath.isEmpty, let file = ReopenPolicy.fileURL(documentPath: w.documentPath) { target = file }
        else if !w.documentPath.isEmpty { return false }
        else if let page = ReopenPolicy.pageURL(w.url) { target = page }
        else { return false }
        let appURL = app?.bundleURL ?? ReopenPolicy.appPaths(named: w.app).map { URL(fileURLWithPath: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
        guard let appURL else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([target], withApplicationAt: appURL, configuration: config)
        return true
    }
}
