import Foundation
import FocusBrain
import FocusJudge

/// What happens when you are warned and stay away. The warning itself (a note or a card) is the brain's; everything after it is this ladder,
/// which keeps climbing while the brain still says "interrupted". Dismissing a card does not stop it; being back on task does.
/// Owner, 2026-10-13: "if the user doesn't get back on task after getting warned ... proactively check ... more punishments ... much more proactive".
public enum EscalationStep: Int, Comparable, Sendable {
    /// The warning only.
    case warned = 0
    /// Focus asks "Are you working on <task>?" and reads the window again.
    case checkIn
    /// The pause screen, with the easy way out held back for a few seconds.
    case pauseScreen
    /// The app you drifted into is hidden and the task comes forward, then again every `enforceEvery` seconds.
    case enforce
    public static func < (a: EscalationStep, b: EscalationStep) -> Bool { a.rawValue < b.rawValue }
}

public struct EscalationPlan: Equatable, Sendable {
    /// Seconds after the warning at which each step begins.
    public var checkInAfter: Double, pauseAfter: Double, enforceAfter: Double
    public var enforceEvery: Double
    /// Seconds before the pause screen lets you explain the window. Only "Back to task" works until then.
    public var holdSeconds: Double

    public static let standard = EscalationPlan(checkInAfter: 40, pauseAfter: 100, enforceAfter: 200, enforceEvery: 120, holdSeconds: 30)
    public static let strict = EscalationPlan(checkInAfter: 20, pauseAfter: 45, enforceAfter: 120, enforceEvery: 60, holdSeconds: 45)

    /// Gentle has no ladder: it is the preset for people who want a single quiet note.
    public static func of(_ p: Preset) -> EscalationPlan? {
        switch p { case .gentle: return nil; case .standard: return .standard; case .strict: return .strict }
    }

    public func step(after seconds: Double) -> EscalationStep {
        if seconds >= enforceAfter { return .enforce }
        if seconds >= pauseAfter { return .pauseScreen }
        if seconds >= checkInAfter { return .checkIn }
        return .warned
    }

    /// Which enforcement round (1, 2, ...) is due at this many seconds, so each fires once.
    public func enforceRound(after seconds: Double) -> Int {
        seconds < enforceAfter ? 0 : 1 + Int((seconds - enforceAfter) / max(1, enforceEvery))
    }

    /// The least gray the screen may be (percent) at this step, whatever the brain's own veil says.
    public static func veilFloor(_ s: EscalationStep) -> Int {
        // Full gray from the check-in on: the owner asked for the maximum.
        switch s { case .warned: return 0; case .checkIn, .pauseScreen, .enforce: return 100 }
    }
}

/// Apps that are never hidden as a consequence: Focus itself and the system's own surfaces.
public enum Enforcement {
    static let protected: Set<String> = ["focus", "finder", "system settings", "loginwindow", "dock", "control center"]
    public static func canHide(_ app: String?) -> Bool {
        guard let a = app?.trimmingCharacters(in: .whitespaces).lowercased(), !a.isEmpty else { return false }
        return !protected.contains(a)
    }
}

/// What the last step of the ladder does to the thing you drifted into. The first time it moves you off it without closing anything:
/// it switches the browser to the tab you were last working in. Later rounds hide the app, and on Strict they close the browser tab.
/// Owner, 2026-10-13: "switches tabs first, later on it closes it on strict mode".
public enum EnforceAction: Equatable, Sendable { case switchAway, hide, close }

extension Enforcement {
    /// Browsers Focus can steer through AppleScript. Arc and others are left out: their scripting is not the same and I have not checked it.
    static let browsers: Set<String> = ["safari", "google chrome", "brave browser", "microsoft edge"]
    public static func isBrowser(_ app: String?) -> Bool { app.map { browsers.contains($0.trimmingCharacters(in: .whitespaces).lowercased()) } ?? false }

    /// `performed` counts the rounds already carried out this warning (0 for the first).
    public static func action(performed: Int, preset: Preset, switching: Bool, closing: Bool) -> EnforceAction {
        if performed == 0 { return switching ? .switchAway : .hide }
        return preset == .strict && closing ? .close : .hide
    }

    /// A tab is closed only when Focus can name it exactly (a browser with an address), it is not private and not on the never-judged list.
    /// Other apps are never quit: that could lose unsaved work, so they are hidden instead.
    public static func mayClose(_ w: WindowSnapshot?, neverJudged: [String], skipPersonal: Bool) -> Bool {
        guard let w, canHide(w.app), isBrowser(w.app), !w.url.isEmpty else { return false }
        let m = Moment(task: "", app: w.app, windowTitle: w.title, url: w.url, documentPath: w.documentPath)
        if Rules.isSensitive(m) { return false }
        if skipPersonal, Rules.isNeverJudged(m, apps: neverJudged) { return false }
        return true
    }
}

/// AppleScript text for steering a browser tab. Only builds strings; the app runs them (focus-app/Tabs.swift), because that needs the
/// user's Automation permission. Addresses from the page are untrusted, so they are escaped as data and never become script.
public enum TabScript {
    /// The address of the front window's current tab in a Chromium browser, which does not report it through Accessibility.
    /// Empty for a private window, so a private tab is never read or closed. Safari reports its address through Accessibility already.
    public static func currentURL(app: String) -> String? {
        guard let name = appName(app), !isSafari(name) else { return nil }
        return """
        with timeout of 2 seconds
        tell application \(quoted(name))
            try
                if (count of windows) is 0 then return ""
                if (mode of front window) is "incognito" then return ""
                return URL of active tab of front window
            end try
        end tell
        return ""
        end timeout
        """
    }

    /// The name AppleScript knows the browser by.
    public static func appName(_ app: String) -> String? {
        switch app.trimmingCharacters(in: .whitespaces).lowercased() {
        case "safari": return "Safari"
        case "google chrome": return "Google Chrome"
        case "brave browser": return "Brave Browser"
        case "microsoft edge": return "Microsoft Edge"
        default: return nil
        }
    }

    /// An address with its scheme, query and fragment removed, so a tab that only changed its query still matches.
    static func bare(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = u.range(of: "://") { u = String(u[r.upperBound...]) }
        if let i = u.firstIndex(where: { $0 == "?" || $0 == "#" }) { u = String(u[..<i]) }
        return u
    }

    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") + "\""
    }

    private static func isSafari(_ name: String) -> Bool { name == "Safari" }
    private static func starts(_ var_: String, _ url: String) -> String {
        let b = bare(url)
        return "((\(var_) starts with \(quoted("https://" + b))) or (\(var_) starts with \(quoted("http://" + b))))"
    }

    /// Brings the tab at `url` forward (any window of that browser). Prints "ok" when it found one, else "none".
    public static func switchTo(app: String, url: String) -> String? {
        guard let name = appName(app), !bare(url).isEmpty else { return nil }
        let pick = isSafari(name) ? "set current tab of w to t" : "set active tab index of w to i"
        return """
        with timeout of 3 seconds
        tell application \(quoted(name))
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    try
                        if \(starts("(URL of t)", url)) then
                            \(pick)
                            set index of w to 1
                            return "ok"
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return "none"
        end timeout
        """
    }

    /// Closes the front window's current tab only if it is still at `url`. Prints "ok", or "changed" when the tab is not that page any more.
    public static func close(app: String, url: String) -> String? {
        guard let name = appName(app), !bare(url).isEmpty else { return nil }
        let current = isSafari(name) ? "current tab of front window" : "active tab of front window"
        return """
        with timeout of 3 seconds
        tell application \(quoted(name))
            try
                set t to \(current)
                if \(starts("(URL of t)", url)) then
                    close t
                    return "ok"
                end if
            end try
        end tell
        return "changed"
        end timeout
        """
    }
}
