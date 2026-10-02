import AppKit
import ApplicationServices
import FocusUI

/// Reads the frontmost app and its focused window through the Accessibility API: app name, window title and the document or
/// page address the window reports. It does not read window text yet. Without Accessibility permission it returns the app name only.
/// UNVERIFIED against real windows: the permission has to be granted by the user in System Settings, and this has only been compiled.
public struct AXWindowSource: WindowSource {
    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system's own prompt that points the user at Privacy & Security > Accessibility. Never grants anything by itself.
    nonisolated(unsafe) private static var prompted = false
    public static func promptForAccess() {
        // The system dialog adds Focus to the Accessibility list; once per launch is enough, more only nags.
        guard !prompted else { return }
        prompted = true
        let opts = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    public func current() -> WindowSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let name = app.localizedName ?? ""
        guard isTrusted else { return WindowSnapshot(app: name, title: "") }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.25)   // a hung app must not freeze Focus
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &win) == .success, let window = win else {
            return WindowSnapshot(app: name, title: "")
        }
        let w = window as! AXUIElement
        let title = Self.string(w, kAXTitleAttribute)
        let (url, path) = Self.address(Self.string(w, kAXDocumentAttribute))
        return WindowSnapshot(app: name, title: title, url: url, documentPath: path)
    }

    static func string(_ el: AXUIElement, _ attr: String) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let s = v as? String else { return "" }
        return s
    }

    /// A window's AXDocument is a file:// URL for documents and the page address for browsers.
    static func address(_ doc: String) -> (url: String, path: String) {
        if doc.hasPrefix("file://"), let p = URL(string: doc)?.path { return ("", p) }
        if doc.hasPrefix("http://") || doc.hasPrefix("https://") { return (doc, "") }
        return ("", "")
    }
}
