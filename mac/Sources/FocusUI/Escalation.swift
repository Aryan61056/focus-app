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
    /// Browsers Focus can steer through AppleScript. Arc and Dia are in since their dictionaries (`sdef`) were read: both have spaces (Arc `space`,
    /// Dia `profile`) with their own tabs and a `focus` command, which the scripts below use. Firefox and others are still out.
    static let browsers: Set<String> = ["safari", "google chrome", "brave browser", "microsoft edge", "comet", "arc", "dia"]
    /// Browsers that keep several spaces of tabs inside one window (Arc's Spaces, Dia's profiles). A place there is a tab in a space, so the
    /// window alone cannot say where you were. Their scripting is not the same as Chrome's: see `TabScript.switchTo` and the checks of 2026-10-17.
    static let spaceBrowsers: Set<String> = ["arc", "dia"]
    public static func isSpaceBrowser(_ app: String?) -> Bool { app.map { spaceBrowsers.contains($0.trimmingCharacters(in: .whitespaces).lowercased()) } ?? false }
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
        guard let name = appName(app), !isSafari(name), !Enforcement.isSpaceBrowser(name) else { return nil }
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

    /// The front tab of Arc or Dia and the space it sits in, as "address<TAB>space". Arc: the address and the id of the active space (nothing for
    /// an incognito window). Dia: only the name of the active profile, never an address, because its dictionary has no private-window flag to
    /// check first. Nil for any other browser.
    public static func currentTab(app: String) -> String? {
        guard let name = appName(app) else { return nil }
        switch name {
        case "Arc":
            return """
            with timeout of 2 seconds
            tell application "Arc"
                try
                    if (count of windows) is 0 then return ""
                    if (mode of front window) is "incognito" then return ""
                    return (URL of active tab of front window) & (character id 9) & ((id of active space of front window) as text)
                end try
            end tell
            return ""
            end timeout
            """
        case "Dia":
            return """
            with timeout of 2 seconds
            tell application "Dia"
                try
                    if (count of windows) is 0 then return ""
                    return (character id 9) & ((name of active profile of front window) as text)
                end try
            end tell
            return ""
            end timeout
            """
        default: return nil
        }
    }

    /// Splits `currentTab`'s answer. A single field is an address with no space.
    public static func parseCurrentTab(_ raw: String) -> (url: String, space: String) {
        let parts = raw.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return (raw.trimmingCharacters(in: .whitespacesAndNewlines), "") }
        return (parts[0].trimmingCharacters(in: .whitespacesAndNewlines), parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The name AppleScript knows the browser by.
    public static func appName(_ app: String) -> String? {
        switch app.trimmingCharacters(in: .whitespaces).lowercased() {
        case "safari": return "Safari"
        case "google chrome": return "Google Chrome"
        case "brave browser": return "Brave Browser"
        case "microsoft edge": return "Microsoft Edge"
        case "comet": return "Comet"
        case "arc": return "Arc"
        case "dia": return "Dia"
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

    /// Brings the tab at `url` forward (any window of that browser). Prints "ok" when it found one, else "none". In Arc and Dia the tab may be in
    /// another space, so the space is brought forward first, and a tab in the space `space` you worked in is preferred over the same address elsewhere.
    public static func switchTo(app: String, url: String, space: String = "") -> String? {
        guard let name = appName(app), !bare(url).isEmpty else { return nil }
        if Enforcement.isSpaceBrowser(name) { return spaceScript(name: name, condition: starts("(URL of t)", url), space: space) }
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

    /// Brings forward the tab whose title contains `title`, for a page whose address changed since Focus read it (a single-page app, a redirect)
    /// or that Focus never read an address for (Dia). Too short a title is nil: it would match the wrong tab. Prints "ok" or "none".
    public static func switchToTitle(app: String, title: String, space: String = "") -> String? {
        guard let name = appName(app) else { return nil }
        let want = TaskPlaces.pageTitle(title, app: app)
        guard want.count >= 6 else { return nil }
        if Enforcement.isSpaceBrowser(name) { return spaceScript(name: name, condition: "((title of t) contains \(quoted(want)))", space: space) }
        let pick = isSafari(name) ? "set current tab of w to t" : "set active tab index of w to i"
        let titleOf = isSafari(name) ? "name of t" : "title of t"   // Safari calls a tab's title its name, Chromium browsers call it title
        return """
        with timeout of 3 seconds
        tell application \(quoted(name))
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    try
                        if (\(titleOf)) contains \(quoted(want)) then
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

    /// The Arc and Dia version: look through every window's spaces (Arc `spaces of w`, Dia `profiles of w`), first the one you worked in, then
    /// the rest; bring that space forward (`focus`), then the tab (Arc `select`, Dia `focus`), then the window to the front.
    static func spaceScript(name: String, condition: String, space: String) -> String {
        let wanted = quoted(space)
        if name == "Arc" {
            return """
            with timeout of 3 seconds
            set wanted to \(wanted)
            repeat with pass from 1 to 2
                tell application "Arc"
                    repeat with w in windows
                        repeat with s in spaces of w
                            if pass = 2 or wanted is "" or ((id of s) as text) is wanted then
                                repeat with t in tabs of s
                                    try
                                        if \(condition) then
                                            try
                                                tell s to focus
                                            end try
                                            tell t to select
                                            try
                                                set index of w to 1
                                            end try
                                            return "ok"
                                        end if
                                    end try
                                end repeat
                            end if
                        end repeat
                    end repeat
                end tell
                if wanted is "" then exit repeat
            end repeat
            return "none"
            end timeout
            """
        }
        return """
        with timeout of 3 seconds
        set wanted to \(wanted)
        repeat with pass from 1 to 2
            tell application "Dia"
                repeat with w in windows
                    repeat with p in profiles of w
                        if pass = 2 or wanted is "" or ((name of p) as text) is wanted then
                            repeat with t in tabs of p
                                try
                                    if \(condition) then
                                        try
                                            focus p
                                        end try
                                        focus t
                                        return "ok"
                                    end if
                                end try
                            end repeat
                        end if
                    end repeat
                end repeat
            end tell
            if wanted is "" then exit repeat
        end repeat
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
