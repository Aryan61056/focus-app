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
        let want = norm(target.title)

        if !target.documentPath.isEmpty {
            let same = cands.indices.filter { cands[$0].documentPath == target.documentPath }
            if let exact = same.first(where: { norm(cands[$0].title) == want }) { return exact }
            if let first = same.first { return first }
        }
        guard !want.isEmpty else { return nil }
        if let exact = cands.indices.first(where: { norm(cands[$0].title) == want }) { return exact }
        let partial = cands.indices.filter {
            let have = norm(cands[$0].title)
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
}
