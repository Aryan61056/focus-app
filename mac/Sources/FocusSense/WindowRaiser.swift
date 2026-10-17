import AppKit
import ApplicationServices
import FocusUI

/// Brings one particular window of an app forward, not just the app. Activating an app raises whichever of its windows was in front, so
/// "Back to task" landed in the wrong Xcode project, the wrong Pages document or the wrong terminal. The match is pure (and tested);
/// the raising uses Accessibility, which Focus already needs to read window titles. Without the permission it does nothing and the caller
/// falls back to bringing the app forward.
public enum WindowRaiser {
    public struct Candidate: Equatable, Sendable {
        public var title: String, documentPath: String
        public init(title: String, documentPath: String = "") { self.title = title; self.documentPath = documentPath }
    }

    /// Which of an app's windows is `target`, or nil when none is clearly it. The same file wins, then the same title, then a title that
    /// contains the other (a document that gained "- Edited"); an ambiguous partial match is nil, because the wrong window is worse than the app.
    public static func pick(for target: WindowSnapshot, among cands: [Candidate]) -> Int? {
        func norm(_ s: String) -> String { TaskPlaces.pageTitle(s, app: target.app).lowercased() }
        // Dia titles its windows "<profile>: <page title>" (read on the real app, 2026-10-17); without the profile the title is the page's.
        func windowNorm(_ s: String) -> String {
            let lead = target.space + ": "
            if !target.space.isEmpty, s.lowercased().hasPrefix(lead.lowercased()) { return norm(String(s.dropFirst(lead.count))) }
            return norm(s)
        }
        let want = norm(target.title)

        if !target.documentPath.isEmpty {
            let same = cands.indices.filter { cands[$0].documentPath == target.documentPath }
            if let exact = same.first(where: { windowNorm(cands[$0].title) == want }) { return exact }
            if let first = same.first { return first }
        }
        guard !want.isEmpty else { return nil }
        if let exact = cands.indices.first(where: { windowNorm(cands[$0].title) == want }) { return exact }
        let partial = cands.indices.filter {
            let have = windowNorm(cands[$0].title)
            guard min(have.count, want.count) >= 6 else { return false }
            return have.contains(want) || want.contains(have)
        }
        return partial.count == 1 ? partial[0] : nil
    }

    /// Makes the app the front app through Accessibility, which works when asking it to activate does not (an app only activates another
    /// cooperatively on recent macOS). Does nothing without the permission.
    @MainActor public static func bringForward(pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    /// Raises the matching window of the process and makes it the app's main and focused window; a minimized one is restored.
    /// True when a window was found and raised.
    @MainActor public static func raise(pid: pid_t, matching target: WindowSnapshot) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)   // a hung app must not freeze Focus
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) != .success || (ref as? [AXUIElement])?.isEmpty != false {
            askForAccessibility(app)   // an Electron app shows its windows only after this; the next trip finds them
        }
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success, let windows = ref as? [AXUIElement], !windows.isEmpty else { return false }
        let cands = windows.map {
            Candidate(title: AXWindowSource.string($0, kAXTitleAttribute),
                      documentPath: AXWindowSource.address(AXWindowSource.string($0, kAXDocumentAttribute)).path)
        }
        guard let i = pick(for: target, among: cands) else { return false }
        let w = windows[i]
        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minimized) == .success, (minimized as? Bool) == true {
            AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        let raised = AXUIElementPerformAction(w, kAXRaiseAction as CFString) == .success
        AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, w)
        return raised
    }

    /// Electron apps (VS Code, Slack, Notion, Discord, Obsidian) build their accessibility tree only when asked, so their windows and tabs are
    /// invisible to Focus until then. Asking is harmless to other apps (they answer "unsupported"). The app keeps it on until it quits.
    @MainActor static func askForAccessibility(_ app: AXUIElement) {
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Every tab strip button in every window of the app, with its window: a tab bar is an AXTabGroup whose children are radio buttons or tabs
    /// (Terminal, Finder, Firefox, Preview, TextEdit, Xcode and others). Bounded, so a huge window cannot stall Focus.
    @MainActor static func tabButtons(app: AXUIElement, windows: [AXUIElement]) -> [(window: AXUIElement, button: AXUIElement, title: String)] {
        var found: [(AXUIElement, AXUIElement, String)] = []
        for win in windows {
            var queue: [(AXUIElement, Int)] = [(win, 0)], seen = 0
            while !queue.isEmpty, seen < 160 {
                let (cur, depth) = queue.removeFirst(); seen += 1
                if AXWindowSource.string(cur, kAXRoleAttribute) == "AXTabGroup" {
                    for b in PositionReader.children(cur) {
                        let role = AXWindowSource.string(b, kAXRoleAttribute)
                        guard role == "AXRadioButton" || role == "AXTab" else { continue }
                        var title = AXWindowSource.string(b, kAXTitleAttribute)
                        if title.isEmpty { title = AXWindowSource.string(b, kAXDescriptionAttribute) }
                        if !title.isEmpty { found.append((win, b, title)) }
                    }
                    continue
                }
                if depth < 6 { queue += PositionReader.children(cur).prefix(24).map { ($0, depth + 1) } }
            }
        }
        return found
    }

    /// Presses the tab whose title is `target`'s, in whichever window of the process holds it, then raises that window. This is what takes
    /// Back to task to the right tab in a terminal, a Finder window, Firefox or a document app, where no script can. True when a tab was pressed.
    @MainActor public static func raiseTab(pid: pid_t, matching target: WindowSnapshot) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success, let windows = ref as? [AXUIElement], !windows.isEmpty else { return false }
        let tabs = tabButtons(app: app, windows: windows)
        guard let i = pick(for: target, among: tabs.map { Candidate(title: $0.title) }) else { return false }
        let t = tabs[i]
        guard AXUIElementPerformAction(t.button, kAXPressAction as CFString) == .success else { return false }
        AXUIElementPerformAction(t.window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        return true
    }

    /// Where this window is on screen (top left origin, like Core Graphics), or nil when it cannot be found or is minimized. A browser whose
    /// tab is not the front one has a window titled for another tab, so with a single window the app has, that window is taken.
    @MainActor public static func frame(pid: pid_t, matching target: WindowSnapshot, allowOnlyWindow: Bool = true) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success, let all = ref as? [AXUIElement], !all.isEmpty else { return nil }
        func minimized(_ w: AXUIElement) -> Bool {
            var m: CFTypeRef?
            return AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &m) == .success && (m as? Bool) == true
        }
        let showing = all.filter { !minimized($0) }
        let cands = showing.map { Candidate(title: AXWindowSource.string($0, kAXTitleAttribute), documentPath: AXWindowSource.address(AXWindowSource.string($0, kAXDocumentAttribute)).path) }
        guard let w = pick(for: target, among: cands).map({ showing[$0] }) ?? (allowOnlyWindow && showing.count == 1 ? showing[0] : nil) else { return nil }
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &pos) == .success, AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &size) == .success,
              let pv = pos, let sv = size, CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, z = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &z) else { return nil }
        return CGRect(origin: p, size: z)
    }
}
