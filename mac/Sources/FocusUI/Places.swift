import Foundation

// Where "Back to task" goes. The brain only remembers the key of the last on-task window, which was enough to name an app, so going
// back raised whichever window of that app was in front, and a tab of the same browser was only found when the distraction was a tab of
// that browser too. This keeps the few places you really worked in (window, tab, document), how long you stayed in each, and decides which
// one is "the task". Names and addresses of on-task windows only, memory only, dropped with the session (CLAUDE.md: sessions save counts,
// never text). Pure, so the choice is tested; the app does the raising (focus-app/Places.swift, FocusSense/WindowRaiser.swift).

/// One window, tab or document you worked in while Focus read it as on task.
public struct TaskPlace: Equatable, Sendable, Identifiable {
    public var window: WindowSnapshot
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
public enum ReturnOutcome: Equatable, Sendable { case exact, appOnly, notFound, alreadyThere }

public struct ReturnReport: Equatable, Sendable {
    public var place: TaskPlace
    public var outcome: ReturnOutcome
    public var at: Double
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
            fresh.dwell = all[i].dwell
            all.remove(at: i)
        }
        all.insert(fresh, at: 0)
        if all.count > Self.capacity, let drop = all.indices.dropFirst().min(by: { all[$0].dwell < all[$1].dwell }) { all.remove(at: drop) }
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
