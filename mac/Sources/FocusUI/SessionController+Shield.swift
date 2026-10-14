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
                var s = Shield(kind: .pause, app: w?.app ?? "", siteKey: w.map(Keys.site) ?? "", since: now(), waitUntil: now())
                if let old = shield { s.asking = old.asking; s.held = old.held; s.message = old.message; s.attemptsLeft = old.attemptsLeft }
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
        if pageHasPass(w) { return }
        let strikes = (frictionStrikes[site] ?? 0) + 1
        frictionStrikes[site] = strikes
        shield = Shield(kind: .friction, app: w.app, siteKey: site, since: t, waitUntil: t)
        lastFrictionEnforce = -1000
        fire(.friction)
    }

    /// Sitting behind the cover is not free. A while after it appears, with no explanation started and no step back to the task,
    /// Focus acts on the site the way the last step of the ladder does, and again every 45 seconds. A site you keep coming back to
    /// is acted on at once: the strike count is the number of rounds already done.
    func enforceOnIdleFriction(_ t: Double) {
        guard isActive, !shadow, prefs.escalate, let s = shield, s.kind == .friction, !s.asking, !s.checking,
              t >= s.waitUntil + Shield.frictionIdle, t - lastFrictionEnforce >= 45 else { return }
        lastFrictionEnforce = t
        runEnforcement(performed: frictionStrikes[s.siteKey] ?? 1)
        frictionStrikes[s.siteKey, default: 1] += 1
    }

    /// The last step of the ladder, shared by the ladder and the friction cover. `performed` is how many rounds came before:
    /// the first switches the browser to the on-task tab, later ones hide the app, and on Strict close the tab.
    @discardableResult func runEnforcement(performed: Int) -> EnforceAction? {
        let w = currentWindow
        let wanted = Enforcement.action(performed: performed, preset: sessionPreset, switching: prefs.switchTabs, closing: prefs.closeOnStrict && closeAllowed)
        var done = false
        if let w {
            switch wanted {
            case .switchAway: done = Enforcement.isBrowser(w.app) && (onSwitchTab?(w, lastOnTask) ?? false)
            case .close: done = onCloseTab?(w) ?? false
            case .hide: break
            }
        }
        lastEnforce = (wanted, done)
        if done { return wanted }
        // Whatever could not be done to the tab falls back to hiding the app, which is how this step always worked.
        if prefs.hideDistractingApp, Enforcement.canHide(w?.app), let app = w?.app { onHideApp?(app); return .hide }
        return nil
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
        guard claimNeedsVerification else { acceptClaim(counted: false); return true }
        let t = now()
        if shield == nil {
            let w = currentWindow
            checkIn = nil
            shield = Shield(kind: .claim, app: w?.app ?? "", siteKey: w.map(Keys.site) ?? "", since: t, waitUntil: t)
        }
        return false
    }

    /// What counts as the same page: the window key (app, site and path) plus the exact title, with a leading "(3)" notification count dropped.
    /// A different video on the same site has a different title, so a pass for one page never covers the next.
    func pageKey(_ w: WindowSnapshot) -> String {
        var title = w.title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        if title.hasPrefix("("), let close = title.firstIndex(of: ")"), title[title.index(after: title.startIndex)..<close].allSatisfy(\.isNumber) {
            title = String(title[title.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return Keys.window(w) + "|" + Keys.fnv(String(title.prefix(200)))
    }
    func pageHasPass(_ w: WindowSnapshot) -> Bool { (passedPages[pageKey(w)] ?? 0) > now() }

    /// When a pass runs out on the page you are on, Focus reads it again as if it had never been explained.
    func expirePasses(_ t: Double) {
        guard isActive, !passedPages.isEmpty else { return }
        let expired = passedPages.filter { $0.value <= t }.map(\.key)
        guard !expired.isEmpty else { return }
        let here = currentWindow.map(pageKey)
        for k in expired { passedPages[k] = nil }
        if let here, expired.contains(here), let w = currentWindow { windowChanged(w) }
    }

    func rememberClaim() { if !pendingClaimWords.isEmpty { acceptedClaimWords.append(pendingClaimWords) } }

    /// The claim passed. Only this page is accepted, only for a few minutes, only in this session, and nothing is learned: the project's
    /// rules are not touched, so one explanation never turns into "that site is fine". `counted` is false for a window Focus had not
    /// flagged, which needed no explanation.
    func acceptClaim(counted: Bool = true) {
        if let w = currentWindow {
            passedPages[pageKey(w)] = now() + Shield.passSeconds(afterClaims: claimsAccepted)
            frictionStrikes[Keys.site(w)] = nil
        }
        if counted { claimsAccepted += 1 }
        shield = nil; shieldHoldStart = nil; checkIn = nil; escalationGate = false
        clearEscalation()
        headsUpAt = nil; driftWatch.clearReadings()
        // Tell the brain this page is fine by rule, which ends the interruption without teaching it anything.
        if let w = currentWindow { windowChanged(w) }
        refreshBanner(now())
    }

    // MARK: the hold
    /// Pressing the hold button. It only counts when explaining is not locked.
    public func beginShieldHold() {
        guard let s = shield, !s.asking, !s.checking, shieldWaitRemaining() == 0, overrideLockRemaining == 0, shieldHoldStart == nil else { return }
        shieldHoldStart = now()
    }
    public func endShieldHold() { shieldHoldStart = nil }
    /// 0 to 1 while the button is held.
    public func shieldHoldProgress() -> Double {
        guard let h = shieldHoldStart else { return 0 }
        return min(1, max(0, (now() - h) / Shield.holdSeconds))
    }
    /// Called a few times a second while the shield is up: a full hold lets the explanation form open.
    public func updateShieldHold() {
        guard shield != nil else { shieldHoldStart = nil; return }
        guard shieldHoldStart != nil, shieldHoldProgress() >= 1, var s = shield else { return }
        shieldHoldStart = nil
        s.held = true
        shield = s
        openExplanation()
    }

    /// Opens the form. It needs the hold to be done and no lock.
    public func openExplanation() {
        guard var s = shield, !s.asking, s.held else { return }
        if shieldWaitRemaining() > 0 { return }
        if overrideLockRemaining > 0 { s.message = CueCopy.lockedLine(Int(overrideLockRemaining.rounded(.up))); shield = s; return }
        s.asking = true; s.message = nil
        shield = s
    }

    public func submitExplanation(_ raw: String) {
        guard var s = shield, s.asking, !s.checking, isActive else { return }
        if overrideLockRemaining > 0 { return }
        let w = currentWindow
        if claimsAccepted >= Shield.claimCap { s.message = CueCopy.claimsUsedUp(Shield.claimCap); shield = s; return }
        if let issue = OverrideClaim.assess(raw, window: w) { s.message = issue.message; shield = s; return }   // a local problem costs no attempt
        // The same explanation again for another page is a pasted one: say what is in this window instead.
        let words = OverrideClaim.content(OverrideClaim.tidy(raw))
        if acceptedClaimWords.contains(where: { OverrideClaim.similarity($0, words) >= 0.6 }) { s.message = OverrideClaim.reusedMessage; shield = s; return }
        guard prefs.useModel, let w else {
            s.message = prefs.useModel ? "Focus cannot see a window to check. Go back to your task." : "The on-device model is switched off in Settings, so Focus cannot check this. Go back to your task."
            shield = s; return
        }
        s.checking = true; s.message = nil
        shield = s
        let m = moment(w), claim = OverrideClaim.tidy(raw), judge = self.judge, key = Keys.window(w)
        let bar = Shield.minConfidence(afterClaims: claimsAccepted)
        pendingClaimWords = OverrideClaim.content(claim)
        tasks.append(Task { [weak self] in
            let r = await Verification.verify(m, claim: claim, with: judge, minConfidence: bar)
            self?.finishExplanation(r, windowKey: key)
        })
    }

    func finishExplanation(_ r: Verification.Result, windowKey: String) {
        guard var s = shield, s.checking else { return }
        // You moved to another window while Focus was reading: that answer is about a window you are no longer in.
        if let w = currentWindow, Keys.window(w) != windowKey { s.checking = false; shield = s; return }
        if r.passed { rememberClaim(); acceptClaim(); return }
        s.checking = false
        s.attemptsLeft -= 1
        if s.attemptsLeft <= 0 {
            let secs = Shield.lockSeconds(after: overrideLocks)
            overrideLocks += 1
            overrideLockedUntil = now() + secs
            s.asking = false; s.held = false; s.attemptsLeft = Shield.attempts
            s.message = CueCopy.lockedLine(Int(secs))
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
        // A wrong explanation costs something at once: Focus acts on the window the way the last step does (hides the app, or on
        // Strict closes the tab). Only a real "this is not on task" reading or an attempt to give Focus orders counts. Focus not being
        // able to tell, a private window or your own "never" rule are not held against you.
        if r.why == .notOnTask || r.why == .injected {
            explainStrikes += 1
            if let did = runEnforcement(performed: explainStrikes), var cur = shield {
                cur.message = (cur.message ?? "") + " " + CueCopy.punishment(did)
                shield = cur
            }
        }
    }

    /// "Back to task": always available, never waits. Brings the task app forward and gives the task a moment to arrive before asking again.
    public func shieldBackToTask() {
        let kind = shield?.kind
        if kind == .pause { escalationGate = false }
        shieldHoldStart = nil
        if kind != .pause { shield = nil }
        blockCurrentSite()
        frictionQuietUntil = now() + 25
        act(.backToTask)
        syncShield()
    }
}

extension SessionController {
    /// Test only: pretends this many explanations were accepted.
    func claimsAcceptedForTesting(_ n: Int) { claimsAccepted = n }

    /// Demo and test only: locks explaining, as two wrong answers would.
    public func debugLock() { overrideLockedUntil = now() + Shield.lockSeconds(after: overrideLocks) }

    /// Demo and test only: shows a shield as if it had just appeared.
    public func debugShowShield(_ kind: Shield.Kind, app: String = "Safari", site: String = "safari|youtube.com", wait: Double = 0,
                                asking: Bool = false, checking: Bool = false, message: String? = nil, attemptsLeft: Int = Shield.attempts) {
        var s = Shield(kind: kind, app: app, siteKey: site, since: now() - (wait > 0 ? wait / 3 : 0), waitUntil: now() + wait)
        s.asking = asking; s.held = asking; s.checking = checking; s.message = message; s.attemptsLeft = attemptsLeft
        shield = s
    }
}
