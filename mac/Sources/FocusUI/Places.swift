import Foundation

// Where "Back to task" goes. The brain only remembers the key of the last on-task window, which was enough to name an app, so going
// back raised whichever window of that app was in front, and a tab of the same browser was only found when the distraction was a tab of
// that browser too. This keeps the few places you really worked in (window, tab, document), how long you stayed in each, and decides which
// one is "the task". Names and addresses of on-task windows only, memory only, dropped with the session (CLAUDE.md: sessions save counts,
// never text). Pure, so the choice is tested; the app does the raising (focus-app/Places.swift, FocusSense/WindowRaiser.swift).

/// Where you were inside a window the last time Focus read it as on task: how far down it was scrolled and where the cursor sat. Numbers
/// only (never the words), memory only, dropped with the session. "Back to task" puts you back there, not at whatever the window drifted to.
public struct PlacePosition: Equatable, Sendable {
    /// 0 is the top, 1 the bottom of the window's main scroll area.
    public var scroll: Double?
    /// The cursor's offset in the focused text field, how much was selected, and how long the text was then.
    public var caret: Int?
    public var selection: Int
    public var characters: Int?
    public init(scroll: Double? = nil, caret: Int? = nil, selection: Int = 0, characters: Int? = nil) {
        self.scroll = scroll.map { min(max($0, 0), 1) }
        self.caret = caret.map { max($0, 0) }
        self.selection = max(selection, 0); self.characters = characters.map { max($0, 0) }
    }
    public var isEmpty: Bool { scroll == nil && caret == nil }

    /// The cursor to restore in text that is now `characters` long: the same offset, or nothing when the text has changed so much that the
    /// offset would land somewhere else (a different paragraph is worse than not moving the cursor).
    public func caretToRestore(nowCharacters now: Int) -> (location: Int, length: Int)? {
        guard let caret else { return nil }
        if let was = characters, abs(now - was) > max(40, was / 5) { return nil }
        guard caret <= now else { return nil }
        return (caret, min(selection, now - caret))
    }

    /// True when scrolling would not visibly move anything.
    public func scrollIsNear(_ other: Double) -> Bool { scroll.map { abs($0 - other) < 0.01 } ?? true }
}

/// One window, tab or document you worked in while Focus read it as on task.
public struct TaskPlace: Equatable, Sendable, Identifiable {
    public var window: WindowSnapshot
    /// Where you were in it, if the app could be asked. Nil is normal: many windows do not say.
    public var position: PlacePosition?
    /// When Focus last read it as on task, and how long you stayed on task in it. Seconds on the controller's clock.
    public var lastSeen: Double
    public var dwell: Double
    public var id: String { TaskPlaces.identity(window) }

    public init(window: WindowSnapshot, lastSeen: Double, dwell: Double = 0) {
        var w = window; w.text = ""   // the words on screen are never kept
        self.window = w; self.lastSeen = lastSeen; self.dwell = dwell
    }

    /// "Pages · Essay draft": the app and a short name for the page or file, for a tooltip or a menu row. The task's own place, never a distraction.
    public var label: String {
        let name = TaskPlaces.shortName(window)
        return name.isEmpty ? window.app : window.app + " \u{00B7} " + name
    }
}

/// How a trip back ended, as far as Focus can tell: the exact window or tab was raised, only the app came forward, nothing could be found,
/// or you were already there.
/// A place that was gone (the document closed, the tab shut, the app quit) and was opened again is `reopened`.
public enum ReturnOutcome: Equatable, Sendable { case exact, appOnly, notFound, alreadyThere, reopened }

public struct ReturnReport: Equatable, Sendable {
    public var place: TaskPlace
    public var outcome: ReturnOutcome
    public var at: Double
}

/// Whether a trip back really arrived. The raise call can succeed and the window still not be in front (an app only activates another
/// cooperatively), so the controller looks again a moment later and compares with this.
public enum LandingCheck {
    /// The place `target` and the window `front` are the same spot: the same file or page, or the same title. A browser whose address has
    /// not been read yet (the address comes from a script a moment later) still matches by page title.
    public static func sameSpot(_ front: WindowSnapshot, _ target: WindowSnapshot) -> Bool {
        guard front.app == target.app else { return false }
        if TaskPlaces.identity(front) == TaskPlaces.identity(target) { return true }
        let a = TaskPlaces.pageTitle(front.title, app: front.app).lowercased(), b = TaskPlaces.pageTitle(target.title, app: target.app).lowercased()
        return a.count >= 6 && a == b && (front.url.isEmpty || target.url.isEmpty)
    }
}

public struct TaskPlaces: Equatable, Sendable {
    /// Places kept. The one with the least time in it goes first when a sixth turns up, so a glance never pushes out the place you live in.
    public static let capacity = 5
    /// Staying this long on task in one place makes it somewhere you were working, not somewhere you looked.
    public static let settledSeconds = 45.0

    /// Most recently on task first.
    public private(set) var all: [TaskPlace] = []
    public init() {}

    public mutating func reset() { all = [] }

    /// What makes two windows the same place: a page by its address without query or fragment, a document by its file, anything else by title.
    /// The same file or page keeps one place when its title changes ("Essay" to "Essay - Edited", "(3) Inbox" to "Inbox").
    public static func identity(_ w: WindowSnapshot) -> String {
        if Keys.host(w.url) != nil { return Keys.window(w) }
        if !w.documentPath.isEmpty { return w.app.lowercased() + "|file:" + w.documentPath }
        return Keys.window(w)
    }

    /// Focus read this window as on task.
    public mutating func noteOnTask(_ w: WindowSnapshot, at t: Double) {
        guard !w.app.isEmpty else { return }
        var fresh = TaskPlace(window: w, lastSeen: t)
        if let i = all.firstIndex(where: { $0.id == fresh.id }) {
            fresh.dwell = all[i].dwell; fresh.position = all[i].position
            all.remove(at: i)
        }
        all.insert(fresh, at: 0)
        if all.count > Self.capacity, let drop = all.indices.dropFirst().min(by: { all[$0].dwell < all[$1].dwell }) { all.remove(at: drop) }
    }

    /// Whether `w` is somewhere Focus has read as on task this session.
    public func contains(_ w: WindowSnapshot) -> Bool { all.contains { $0.id == Self.identity(w) } }

    /// Remember where you are in `w`. Ignored for a window that was never read as on task, and an empty reading never erases a good one.
    public mutating func notePosition(_ w: WindowSnapshot, _ p: PlacePosition?) {
        let id = Self.identity(w)
        guard let p, !p.isEmpty, let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].position = p
    }

    /// Time spent on task in `w`. Ignored for a window that was never read as on task.
    public mutating func addDwell(_ w: WindowSnapshot, seconds: Double) {
        let id = Self.identity(w)
        guard seconds > 0, let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].dwell += seconds
    }

    /// Where "Back to task" should go: the place you were just in if you really worked there; otherwise the place you spent the most time in,
    /// so a quick look at a reference does not become the task. With nothing settled, the latest.
    public var destination: TaskPlace? {
        guard let last = all.first else { return nil }
        if last.dwell >= Self.settledSeconds { return last }
        if let home = all.max(by: { $0.dwell < $1.dwell }), home.dwell >= Self.settledSeconds { return home }
        return last
    }

    /// Everything to try, best first. If the first cannot be found (the app was quit, the window closed) the next one is tried.
    public var candidates: [TaskPlace] {
        guard let d = destination else { return [] }
        return [d] + all.filter { $0.id != d.id }
    }

    /// Other places you really worked in (settled, not just glanced at), oldest first, for bringing the whole task back at once: the page and
    /// the notes beside it, not only one of them. At most two, so a trip back never rearranges the whole screen.
    public func companions(of dest: TaskPlace) -> [TaskPlace] {
        Array(all.filter { $0.id != dest.id && $0.dwell >= Self.settledSeconds }.sorted { $0.lastSeen < $1.lastSeen }.suffix(2))
    }

    /// Up to two other places, for the menu bar: "or go here instead".
    public var alternatives: [TaskPlace] { Array(candidates.dropFirst().prefix(2)) }

    // MARK: names

    /// The tail a browser adds to its window title ("Essay - Google Docs - Google Chrome").
    static let browserNames = ["google chrome", "safari", "brave browser", "microsoft edge", "comet", "firefox", "arc"]

    /// The page or file as a short name: the title without the browser's own tail, or the host of an address, or the file's name.
    public static func shortName(_ w: WindowSnapshot) -> String {
        var t = pageTitle(w.title, app: w.app)
        if t.isEmpty, let h = Keys.host(w.url)?.host { t = h.hasPrefix("www.") ? String(h.dropFirst(4)) : h }
        if t.isEmpty, !w.documentPath.isEmpty { t = (w.documentPath as NSString).lastPathComponent }
        return t.count > 28 ? String(t.prefix(27)) + "\u{2026}" : t
    }

    /// A window title without a leading "(3)" notification count and without the browser's own name at the end.
    public static func pageTitle(_ raw: String, app: String) -> String {
        var t = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if t.hasPrefix("("), let close = t.firstIndex(of: ")"), t[t.index(after: t.startIndex)..<close].allSatisfy(\.isNumber), close > t.index(after: t.startIndex) {
            t = String(t[t.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        for sep in [" - ", " \u{2014} ", " \u{2013} ", " | "] {
            if let r = t.range(of: sep, options: .backwards) {
                let tail = t[r.upperBound...].lowercased()
                if tail == app.lowercased() || browserNames.contains(tail) { t = String(t[..<r.lowerBound]); break }
            }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
