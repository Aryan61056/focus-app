import AppKit
import ApplicationServices
import FocusUI

/// Reads and restores where you are inside the front window: how far its main scroll area is scrolled and where the text cursor sits.
/// Numbers only. It never reads the text in the window (the length of the text is asked of the app as a number). It needs the Accessibility
/// permission Focus already uses, and does nothing without it. Many windows do not expose a scroll bar or a cursor; then there is nothing
/// to note and nothing to put back, and that is normal.
public enum PositionReader {
    @MainActor static func app(named name: String) -> NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication, front.localizedName == name,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return front
    }

    static func element(_ e: AXUIElement, _ attr: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &ref) == .success, let r = ref, CFGetTypeID(r) == AXUIElementGetTypeID() else { return nil }
        return (r as! AXUIElement)
    }

    static func children(_ e: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &ref) == .success, let list = ref as? [AXUIElement] else { return [] }
        return list
    }

    static func number(_ e: AXUIElement, _ attr: String) -> Double? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &ref) == .success, let n = ref as? NSNumber else { return nil }
        return n.doubleValue
    }

    static func range(_ e: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXSelectedTextRangeAttribute as CFString, &ref) == .success, let v = ref, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        return AXValueGetValue(v as! AXValue, .cfRange, &r) ? r : nil
    }

    /// The window's main scroll area: the one around the focused element if there is one, else the first found just inside the window.
    static func scrollArea(focused: AXUIElement?, window: AXUIElement?) -> AXUIElement? {
        var e = focused
        for _ in 0..<12 {
            guard let cur = e else { break }
            if AXWindowSource.string(cur, kAXRoleAttribute) == "AXScrollArea" { return cur }
            e = element(cur, kAXParentAttribute)
        }
        guard let window else { return nil }
        var queue: [(AXUIElement, Int)] = [(window, 0)], seen = 0
        while !queue.isEmpty, seen < 80 {
            let (cur, depth) = queue.removeFirst(); seen += 1
            if AXWindowSource.string(cur, kAXRoleAttribute) == "AXScrollArea" { return cur }
            if depth < 4 { queue += children(cur).prefix(12).map { ($0, depth + 1) } }
        }
        return nil
    }

    @MainActor public static func read(of w: WindowSnapshot) -> PlacePosition? {
        guard AXIsProcessTrusted(), let front = app(named: w.app) else { return nil }
        let root = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.4)
        let focused = element(root, kAXFocusedUIElementAttribute), window = element(root, kAXFocusedWindowAttribute)
        // Never note a password field.
        if let f = focused, AXWindowSource.string(f, kAXSubroleAttribute) == "AXSecureTextField" { return nil }
        var scroll: Double?
        if let area = scrollArea(focused: focused, window: window), let bar = element(area, kAXVerticalScrollBarAttribute) { scroll = number(bar, kAXValueAttribute) }
        var caret: Int?, selection = 0, characters: Int?
        if let f = focused, let r = range(f), r.location >= 0 {
            caret = r.location; selection = max(r.length, 0)
            characters = number(f, kAXNumberOfCharactersAttribute).map { Int($0) }
        }
        let p = PlacePosition(scroll: scroll, caret: caret, selection: selection, characters: characters)
        return p.isEmpty ? nil : p
    }

    /// Puts the scroll and cursor back. True when what was asked for is now in place (or already was). The cursor first, because moving it
    /// can scroll the view, then the scroll.
    @MainActor public static func restore(_ w: WindowSnapshot, _ p: PlacePosition) -> Bool {
        guard AXIsProcessTrusted(), let front = app(named: w.app) else { return false }
        let root = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.4)
        let focused = element(root, kAXFocusedUIElementAttribute), window = element(root, kAXFocusedWindowAttribute)
        var done = false, failed = false
        if p.caret != nil, let f = focused, let now = number(f, kAXNumberOfCharactersAttribute).map({ Int($0) }) {
            if let want = p.caretToRestore(nowCharacters: now) {
                var r = CFRange(location: want.location, length: want.length)
                if let cur = range(f), cur.location == r.location, cur.length == r.length { done = true }
                else if let v = AXValueCreate(.cfRange, &r), AXUIElementSetAttributeValue(f, kAXSelectedTextRangeAttribute as CFString, v) == .success { done = true }
                else { failed = true }
            }
        }
        if let s = p.scroll, let area = scrollArea(focused: focused, window: window), let bar = element(area, kAXVerticalScrollBarAttribute), let cur = number(bar, kAXValueAttribute) {
            if p.scrollIsNear(cur) { done = true }
            else if AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: s)) == .success,
                    let after = number(bar, kAXValueAttribute), abs(after - s) < 0.05 { done = true }
            else { failed = true }
        }
        return done && !failed
    }
}
