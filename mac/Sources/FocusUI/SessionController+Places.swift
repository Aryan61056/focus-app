import Foundation
import FocusBrain
import FocusJudge

/// "Back to task" goes to the place you were working, not just to the app. Which place is Places.swift; raising it is the app's job
/// (`onGoToPlace`: the window by Accessibility, a tab in any app by its tab bar, a browser tab by AppleScript, a closed document or page
/// opened again). The brain still emits `bringBack(windowKey)`, so its traces are unchanged. When the place has come forward, the scroll and
/// cursor are put back where they were.
extension SessionController {
    /// How often the scroll and cursor of the place you are working in are noted.
    static let positionEverySeconds = 3.0

    /// Hushd read this window as on task: remember it as somewhere you worked.
    func notePlace(_ w: WindowSnapshot) {
        let before = places.candidates.map(\.id)
        places.noteOnTask(w, at: now())
        if places.candidates.map(\.id) != before { placesVersion &+= 1 }
    }

    /// Counts the time you stay on task in a place you have worked in, so a place you live in outweighs one you glanced at. Also notes where
    /// you are in the window you are working in, and finishes putting the scroll and cursor back after a trip.
    func tickPlaces(_ t: Double) {
        defer { lastPlaceTick = t }
        retrySpot()
        guard isActive, !isPaused, presence.state == "resting", let w = currentWindow, let last = lastPlaceTick else { return }
        let before = places.candidates.map(\.id)
        places.addDwell(w, seconds: min(max(0, t - last), 5))   // a Mac that slept does not count
        if places.candidates.map(\.id) != before { placesVersion &+= 1 }
        // A browser keeps each tab's scroll itself, and its text fields are the page's: nothing to note there.
        if prefs.restoreSpot, !shadow, pendingSpot == nil, !Enforcement.isBrowser(w.app), places.contains(w), t - (lastPositionAt ?? -.infinity) >= Self.positionEverySeconds, let read = onReadPosition {
            lastPositionAt = t
            places.notePosition(w, read(w))
        }
    }

    /// The place "Back to task" would go to now, for tooltips and the menu. Nil before you have been on task anywhere this session.
    public var returnPlace: TaskPlace? { _ = placesVersion; return places.destination }

    /// Other places you worked in, for "go here instead".
    public var otherPlaces: [TaskPlace] { _ = placesVersion; return places.alternatives }

    /// The key from any app: Back to task, when a session is running.
    public func backToTaskFromShortcut() {
        guard isActive else { return }
        act(.backToTask)
    }

    /// A link another tool opened (`focusapp://back`). True when it was understood and acted on. A burst of links counts once, so a page or a
    /// script that opens it in a loop cannot keep pulling windows around.
    @discardableResult public func handleLink(_ url: URL) -> Bool {
        guard prefs.allowBackLink, isActive, let action = FocusLink.action(from: url) else { return false }
        let t = date()
        if let last = lastLinkAt, t.timeIntervalSince(last) < 2 { return true }
        lastLinkAt = t
        switch action { case .backToTask: act(.backToTask) }
        return true
    }

    func markAway() { awayAtPress = (presence.state == "drifting" || presence.state == "interrupted") ? currentWindow : nil }

    /// The place to outline while Hushd is nudging you, or nil. Only once it is a real nudge ("interrupted", after sustained agreement, not the
    /// first doubt), only if you turned it on, never in practice, and not when you are already in that place.
    public var beaconPlace: TaskPlace? {
        guard prefs.beaconRing, isActive, !shadow, presence.state == "interrupted", let d = returnPlace else { return nil }
        if let cur = currentWindow, TaskPlaces.identity(cur) == d.id { return nil }
        // A tab or space inside the window you are in: that window is not "the way back", so there is nothing to outline.
        if let cur = currentWindow, Enforcement.isBrowser(d.window.app), cur.app == d.window.app { return nil }
        return d
    }

    /// The Dock menu's line.
    public var backToTaskTitle: String { returnPlace.map { "Back to \($0.label)" } ?? "Back to task" }

    /// After a trip you asked for: the app you drifted into is hidden, if you turned that on. Hiding is Command-H: nothing is closed.
    /// Never the app you went back to, never a place you worked in, never Hushd, Finder or a system app, never an app on the never-judged list.
    private func putAway(after place: TaskPlace) {
        let drifted = awayAtPress; awayAtPress = nil
        guard prefs.putAwayOnReturn, !shadow, !ladderReturning, let d = drifted, d.app != place.window.app, Enforcement.canHide(d.app),
              !places.contains(d), !(prefs.skipPersonal && Rules.isNeverJudged(moment(d), apps: prefs.neverJudgedApps)) else { return }
        onHideApp?(d.app)
    }

    /// The brain asked to bring you back. Falls back to the app the brain's key points at when no place was recorded.
    func goBack(windowKey key: String?) {
        let tries = Array(places.candidates.prefix(3))
        guard let first = tries.first else {
            if let key, let app = appByWindowKey[key], !app.isEmpty { onBringBackToApp?(app) }
            return
        }
        if let cur = currentWindow, TaskPlaces.identity(cur) == first.id { awayAtPress = nil; report(first, .alreadyThere); return }
        // The other windows of the task come forward first, so the place itself ends up in front of them and the distraction is behind all of them.
        if prefs.bringWorkingSet && !shadow { for p in places.companions(of: first) { _ = bring(p, reopen: false) } }
        for p in tries {
            let outcome = bring(p)
            if outcome != .notFound { report(p, outcome); startSpotRestore(p, outcome); putAway(after: p); return }
        }
        awayAtPress = nil
        report(first, .notFound)
    }

    /// The menu bar's "go here instead": one of the other places, tried on its own.
    public func goTo(_ place: TaskPlace) {
        guard isActive else { return }
        if let cur = currentWindow, TaskPlaces.identity(cur) == place.id { report(place, .alreadyThere); return }
        markAway()
        let outcome = bring(place)
        report(place, outcome)
        if outcome != .notFound { startSpotRestore(place, outcome); putAway(after: place) }
        // Going back by any path puts the reminder away (see act).
        headsUpAt = nil; bannerHidden = true
        refreshBanner(now())
    }

    // MARK: scroll and cursor

    /// After a trip: puts the scroll and cursor back where they were once the place is in front. A few tries a second apart, because a
    /// document that was just opened may not have laid out yet. Only ever into the very window asked for.
    private func startSpotRestore(_ place: TaskPlace, _ outcome: ReturnOutcome) {
        lastSpotRestored = nil; pendingSpot = nil
        guard prefs.restoreSpot, !shadow, onRestorePosition != nil, outcome != .alreadyThere, !Enforcement.isBrowser(place.window.app) else { return }
        pendingSpot = (place, 0)
    }

    private func retrySpot() {
        guard var s = pendingSpot, let hook = onRestorePosition else { pendingSpot = nil; return }
        // The newest note, not the one from when the trip began.
        let pos = places.all.first { $0.id == s.place.id }?.position ?? s.place.position
        guard let pos, !pos.isEmpty else { pendingSpot = nil; return }
        s.tries += 1
        if let cur = currentWindow, LandingCheck.sameSpot(cur, s.place.window), hook(s.place.window, pos) { lastSpotRestored = true; pendingSpot = nil; return }
        if s.tries >= 4 { lastSpotRestored = false; pendingSpot = nil } else { pendingSpot = s }
    }

    private func report(_ p: TaskPlace, _ o: ReturnOutcome) {
        lastReturn = ReturnReport(place: p, outcome: o, at: now())
        beta?.journal.note(.backToTask, o == .notFound ? 0 : 1)
    }

    private func bring(_ p: TaskPlace, reopen allowReopen: Bool = true) -> ReturnOutcome {
        let allowTabs = prefs.switchTabs && !shadow
        let reopen = allowReopen && prefs.reopenClosed && !shadow && !ladderReturning
        if let hook = onGoToPlace { return hook(p.window, allowTabs, reopen) }
        // Without the app's hook (tests, the guided example): bring the app forward, and the tab if it is the same browser as the one you are in.
        onBringBackToApp?(p.window.app)
        if allowTabs, !ladderReturning, let w = currentWindow, Enforcement.isBrowser(w.app), p.window.app == w.app,
           !p.window.url.isEmpty, !w.url.isEmpty, p.window.url != w.url {
            return (onSwitchTab?(w, p.window) ?? false) ? .exact : .appOnly
        }
        return .appOnly
    }
}
