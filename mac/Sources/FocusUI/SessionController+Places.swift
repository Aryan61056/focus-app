import Foundation
import FocusBrain

/// "Back to task" goes to the place you were working, not just to the app. Which place is Places.swift; raising it is the app's job
/// (`onGoToPlace`: the window by Accessibility, the tab by AppleScript). The brain still emits `bringBack(windowKey)`, so its traces are unchanged.
extension SessionController {
    /// Focus read this window as on task: remember it as somewhere you worked.
    func notePlace(_ w: WindowSnapshot) {
        let before = places.candidates.map(\.id)
        places.noteOnTask(w, at: now())
        if places.candidates.map(\.id) != before { placesVersion &+= 1 }
    }

    /// Counts the time you stay on task in a place you have worked in, so a place you live in outweighs one you glanced at.
    func tickPlaces(_ t: Double) {
        defer { lastPlaceTick = t }
        guard isActive, !isPaused, presence.state == "resting", let w = currentWindow, let last = lastPlaceTick else { return }
        let before = places.candidates.map(\.id)
        places.addDwell(w, seconds: min(max(0, t - last), 5))   // a Mac that slept does not count
        if places.candidates.map(\.id) != before { placesVersion &+= 1 }
    }

    /// The place "Back to task" would go to now, for tooltips and the menu. Nil before you have been on task anywhere this session.
    public var returnPlace: TaskPlace? { _ = placesVersion; return places.destination }

    /// Other places you worked in, for "go here instead".
    public var otherPlaces: [TaskPlace] { _ = placesVersion; return places.alternatives }

    /// The brain asked to bring you back. Falls back to the app the brain's key points at when no place was recorded.
    func goBack(windowKey key: String?) {
        let tries = Array(places.candidates.prefix(3))
        guard let first = tries.first else {
            if let key, let app = appByWindowKey[key], !app.isEmpty { onBringBackToApp?(app) }
            return
        }
        if let cur = currentWindow, TaskPlaces.identity(cur) == first.id { report(first, .alreadyThere); return }
        for p in tries {
            let outcome = bring(p)
            if outcome != .notFound { report(p, outcome); return }
        }
        report(first, .notFound)
    }

    /// The menu bar's "go here instead": one of the other places, tried on its own.
    public func goTo(_ place: TaskPlace) {
        guard isActive else { return }
        if let cur = currentWindow, TaskPlaces.identity(cur) == place.id { report(place, .alreadyThere); return }
        report(place, bring(place))
        // Going back by any path puts the reminder away (see act).
        headsUpAt = nil; bannerHidden = true
        refreshBanner(now())
    }

    private func report(_ p: TaskPlace, _ o: ReturnOutcome) { lastReturn = ReturnReport(place: p, outcome: o, at: now()) }

    private func bring(_ p: TaskPlace) -> ReturnOutcome {
        let allowTabs = prefs.switchTabs && !shadow
        if let hook = onGoToPlace { return hook(p.window, allowTabs) }
        // Without the app's hook (tests, the guided example): bring the app forward, and the tab if it is the same browser as the one you are in.
        onBringBackToApp?(p.window.app)
        if allowTabs, !ladderReturning, let w = currentWindow, Enforcement.isBrowser(w.app), p.window.app == w.app,
           !p.window.url.isEmpty, !w.url.isEmpty, p.window.url != w.url {
            return (onSwitchTab?(w, p.window) ?? false) ? .exact : .appOnly
        }
        return .appOnly
    }
}
