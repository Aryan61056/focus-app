import Foundation
import FocusBrain
import FocusJudge

/// The shield: a screen over everything that has to be answered. Replaces the old hold-to-open and typed-reason shortcuts.
/// The way through is going back to the task, or an explanation that survives two checks: local rules (Override.swift), then the
/// on-device model reading the window with both of its judges (Verification.swift). Two failed explanations lock it for five minutes.
extension SessionController {
    var pauseWanted: Bool { surface?.kind == "gate" || escalationGate }

    /// Brings `shield` in line with the pause screen the ladder or the brain wants. Friction and claim shields are set elsewhere.
    func syncShield() {
        if pauseWanted {
            if shield?.kind != .pause {
                let w = currentWindow
                var s = Shield(kind: .pause, app: w?.app ?? "", siteKey: w.map(Keys.site) ?? "", since: now(), waitUntil: gateHoldUntil ?? now() + 10)
                if let old = shield { s.asking = old.asking; s.message = old.message; s.attemptsLeft = old.attemptsLeft }
                shield = s
            }
        } else if shield?.kind == .pause { shield = nil }
    }

    /// Whole seconds are shown, so this is the exact time left.
    public func shieldWaitRemaining() -> Double { max(0, (shield?.waitUntil ?? 0) - now()) }
    public var overrideLockRemaining: Double { max(0, (overrideLockedUntil ?? 0) - now()) }

    // MARK: friction: the same site, again
    /// Remembers the site you were warned about, once the pause screen is answered or the app is hidden.
    func blockCurrentSite() {
        guard prefs.frictionReturn, !shadow, let w = currentWindow, Enforcement.canHide(w.app) else { return }
        blockedSites[Keys.site(w)] = w.app
    }

    func updateFriction(_ w: WindowSnapshot) {
        let site = Keys.site(w)
        // Leaving the site ends a friction or claim screen; a pause screen belongs to the ladder.
        if let s = shield, s.kind != .pause, s.siteKey != site { shield = nil }
        let t = now()
        guard prefs.frictionReturn, !shadow, shield == nil, t >= frictionQuietUntil, blockedSites[site] != nil, checkIn == nil else { return }
        if let u = passUntil[site], t < u { return }
        shield = Shield(kind: .friction, app: w.app, siteKey: site, since: t, waitUntil: t + Shield.frictionWait)
        fire(.friction)
    }

    // MARK: claims
    /// Saying "this window is part of the task". A window Focus has read as off topic needs an explanation that checks out;
    /// anything else is taken at its word, as before.
    var claimNeedsVerification: Bool {
        guard isActive, !shadow else { return false }
        if presence.state == "interrupted" { return true }
        guard let w = currentWindow else { return false }
        let key = Keys.window(w)
        return readings.first(where: { $0.key == key })?.call == .off
    }

    /// "That was fine", "Yes, this is part of it", "This is part of it". Returns true when it was accepted at once.
    @discardableResult public func claimOnTask() -> Bool {
        guard isActive else { return false }
        guard claimNeedsVerification else { acceptClaim(); return true }
        let t = now()
        if shield == nil {
            let w = currentWindow
            checkIn = nil
            shield = Shield(kind: .claim, app: w?.app ?? "", siteKey: w.map(Keys.site) ?? "", since: t, waitUntil: t + Shield.claimWait)
        }
        return false
    }

    /// The claim passed (or never needed to): Focus learns the window, the climb ends, and the site opens for ten minutes.
    func acceptClaim() {
        if let s = shield { passUntil[s.siteKey] = now() + Shield.passSeconds; blockedSites[s.siteKey] = nil }
        if let w = currentWindow { passUntil[Keys.site(w)] = now() + Shield.passSeconds }
        shield = nil; checkIn = nil; escalationGate = false
        act(.thatWasFine)
        clearEscalation()
        headsUpAt = nil; driftWatch.clearReadings(); refreshBanner(now())
    }

    /// "Explain": opens the form once the wait is over and the lock, if any, has run out.
    public func openExplanation() {
        guard var s = shield, !s.asking else { return }
        if shieldWaitRemaining() > 0 { return }
        if overrideLockRemaining > 0 { s.message = CueCopy.lockedLine(Int(overrideLockRemaining.rounded(.up))); shield = s; return }
        s.asking = true; s.message = nil
        shield = s
    }

    public func submitExplanation(_ raw: String) {
        guard var s = shield, s.asking, !s.checking, isActive else { return }
        if overrideLockRemaining > 0 { return }
        let w = currentWindow
        if let issue = OverrideClaim.assess(raw, window: w) { s.message = issue.message; shield = s; return }   // a local problem costs no attempt
        guard prefs.useModel, let w else {
            s.message = prefs.useModel ? "Focus cannot see a window to check. Go back to your task." : "The on-device model is switched off in Settings, so Focus cannot check this. Go back to your task."
            shield = s; return
        }
        s.checking = true; s.message = nil
        shield = s
        let m = moment(w), claim = OverrideClaim.tidy(raw), judge = self.judge, key = Keys.window(w)
        tasks.append(Task { [weak self] in
            let r = await Verification.verify(m, claim: claim, with: judge)
            self?.finishExplanation(r, windowKey: key)
        })
    }

    func finishExplanation(_ r: Verification.Result, windowKey: String) {
        guard var s = shield, s.checking else { return }
        // You moved to another window while Focus was reading: that answer is about a window you are no longer in.
        if let w = currentWindow, Keys.window(w) != windowKey { s.checking = false; shield = s; return }
        if r.passed { acceptClaim(); return }
        s.checking = false
        s.attemptsLeft -= 1
        if s.attemptsLeft <= 0 {
            overrideLockedUntil = now() + Shield.lockSeconds
            s.asking = false; s.attemptsLeft = Shield.attempts
            s.message = CueCopy.lockedLine(Int(Shield.lockSeconds))
        } else {
            let n = s.attemptsLeft
            switch r.why {
            case .ruleSaysNever: s.message = "You told Focus this never counts for the project. Change that in Projects if it is wrong."
            case .injected: s.message = OverrideClaim.Issue.injected.message
            case .sensitive: s.message = "This is a private window, so Focus cannot read it."
            case .couldNotTell: s.message = "Focus could not tell from the window, so it kept the block. \(n) \(n == 1 ? "try" : "tries") left."
            default: s.message = "Focus read the window again and it does not look like \(taskName). \(n) \(n == 1 ? "try" : "tries") left."
            }
        }
        shield = s
    }

    /// "Back to task": always available, never waits. Brings the task app forward and gives the task a moment to arrive before asking again.
    public func shieldBackToTask() {
        let kind = shield?.kind
        if kind == .pause { escalationGate = false }
        if kind != .pause { shield = nil }
        blockCurrentSite()
        frictionQuietUntil = now() + 25
        act(.backToTask)
        syncShield()
    }
}

extension SessionController {
    /// Demo and test only: locks explaining, as two wrong answers would.
    public func debugLock() { overrideLockedUntil = now() + Shield.lockSeconds }

    /// Demo and test only: shows a shield as if it had just appeared.
    public func debugShowShield(_ kind: Shield.Kind, app: String = "Safari", site: String = "safari|youtube.com", wait: Double = 0,
                                asking: Bool = false, checking: Bool = false, message: String? = nil, attemptsLeft: Int = Shield.attempts) {
        var s = Shield(kind: kind, app: app, siteKey: site, since: now() - (wait > 0 ? wait / 3 : 0), waitUntil: now() + wait)
        s.asking = asking; s.checking = checking; s.message = message; s.attemptsLeft = attemptsLeft
        shield = s
    }
}
