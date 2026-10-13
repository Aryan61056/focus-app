import Foundation
import FocusBrain

/// The cues around the warning: heads-up, banner, friction, rhythm, pressure and the channels outside the app.
/// Nothing here changes what the brain decides; it only adds surfaces and timing around it (see Cues.swift).
extension SessionController {
    /// How long a heads-up stays on screen if you do nothing.
    static let headsUpSeconds = 25.0
    /// A check-in prompt you ignore counts as "yes, keep going" after this long.
    static let checkInPromptSeconds = 90.0

    func resetCues() {
        banner = nil; friction = nil; frictionHoldStart = nil; rhythmPrompt = nil
        driftWatch.reset(); headsUpAt = nil; bannerHidden = false
        blockedSites = [:]; passUntil = [:]; frictionQuietUntil = 0
        workSeconds = 0; lastWorkTick = nil; workBlocks = 0; lastSpokeAt = nil; warnedPressure = .steady
    }

    // MARK: pressure through the day
    /// How hard Focus pushes right now. Steady when the daily goal or progress is switched off, because a goal you cannot see should not push.
    public var pressure: DayPressure {
        guard prefs.paceMatters, prefs.showProgress, prefs.dailyGoalMinutes > 0 else { return .steady }
        return DayPressure.level(goalMinutes: prefs.dailyGoalMinutes, onTaskSeconds: todayOnTaskSeconds(), at: date())
    }

    /// The line on Today that says why Focus is easy or firm, or nil when it is steady.
    public var paceLine: String? {
        let goal = Double(prefs.dailyGoalMinutes) * 60
        let seconds = todayOnTaskSeconds()
        let c = Calendar.current.dateComponents([.hour, .minute], from: date())
        let hour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        let expected = min(1, max(0, (hour - DayPressure.dayStart) / (DayPressure.dayEnd - DayPressure.dayStart))) * goal
        return PaceCopy.line(pressure, goalReached: goal > 0 && seconds >= goal, behindMinutes: max(0, Int(((expected - seconds) / 60).rounded())))
    }

    // MARK: cues outside the app
    /// One place that decides which channels a moment uses. Practice mode stays silent in every channel.
    func fire(_ e: CueEvent, title: String? = nil) {
        guard isActive, !shadow else { return }
        if prefs.hapticTap { onHaptic?(e.firm ? .firm : .light) }
        if prefs.dockBounce, e.bouncesDock { onDockBounce?() }
        let t = now()
        if prefs.speakNudges, e.speaks, let line = CueCopy.spoken(e, title: title ?? ""), !line.isEmpty, (lastSpokeAt.map { t - $0 >= 15 } ?? true) {
            lastSpokeAt = t; onSpeak?(line)
        }
    }

    /// Settings "Try": plays one cue so you can feel or hear it. Not tied to a session.
    public func previewCue(haptic: Bool) {
        if haptic { onHaptic?(.firm) } else { onSpeak?("Back to \(taskName.isEmpty ? "your task" : taskName).") }
    }

    /// How the menu bar ring reads.
    public var menuCue: MenuCue {
        guard isActive, !shadow, prefs.menuBarCue, !isPaused else { return .none }
        if presence.state == "interrupted" { return .away }
        if presence.state == "drifting" || banner?.kind == .early || rhythmPrompt != nil || friction != nil { return .headsUp }
        return .none
    }

    // MARK: banner and heads-up
    func cueBeacon(_ s: String, _ t: Double) {
        if s != "interrupted" { bannerHidden = false }
        if s == "resting" || s == "recovering" { driftWatch.clearReadings(); headsUpAt = nil }
        refreshBanner(t)
    }

    func refreshBanner(_ t: Double) {
        var next: Banner?
        if isActive, !shadow, prefs.showBanner, !isPaused, !gateOpen, checkIn == nil {
            if presence.state == "interrupted", !bannerHidden {
                next = Banner(kind: .reminder, at: banner?.kind == .reminder ? banner!.at : t)
            } else if let h = headsUpAt, presence.state != "interrupted", t - h < Self.headsUpSeconds {
                next = Banner(kind: .early, at: h)
            }
        }
        if banner != next { banner = next }
    }

    /// Feeds every reading the judge or a rule makes to the watcher and raises a heads-up when the recent past looks like a rabbit hole.
    func noteForHeadsUp(_ r: Reading) {
        guard r.source == .model || r.source == .rule else { return }
        driftWatch.note(call: r.call, key: r.key, at: r.at)
        let t = now()
        guard isActive, !shadow, prefs.headsUp, prefs.showBanner, sessionPreset != .gentle, !isPaused,
              presence.state != "interrupted", driftWatch.looksLikeARabbitHole(at: t) else { return }
        driftWatch.markNoticed(at: t); headsUpAt = t
        refreshBanner(t)
        fire(.headsUp)
    }

    /// "Back to task" on the banner.
    public func bannerBackToTask() { headsUpAt = nil; bannerHidden = true; refreshBanner(now()); act(.backToTask) }
    /// "It's part of it" on the heads-up: Focus learns the window belongs, the same as "That was fine".
    public func bannerPartOfIt() { headsUpAt = nil; driftWatch.clearReadings(); refreshBanner(now()); act(.thatWasFine) }
    /// The small cross on the banner. A reminder stays hidden until you have been back on task and drift again.
    public func dismissBanner() { headsUpAt = nil; bannerHidden = true; refreshBanner(now()) }

    func tickCues(_ t: Double) {
        refreshBanner(t)
        tickRhythm(t)
        if friction != nil { updateFrictionHold() }
        else if t - lastFrictionCheck >= 5, let w = currentWindow { lastFrictionCheck = t; updateFriction(w) }
    }

    // MARK: friction before going back
    /// Remembers the site you were warned about, once the pause screen is answered or the app is hidden.
    func blockCurrentSite() {
        guard prefs.frictionReturn, !shadow, let w = currentWindow, Enforcement.canHide(w.app) else { return }
        blockedSites[Keys.site(w)] = w.app
    }

    func updateFriction(_ w: WindowSnapshot) {
        let site = Keys.site(w)
        if let f = friction, f.siteKey != site { friction = nil; frictionHoldStart = nil }
        let t = now()
        guard prefs.frictionReturn, !shadow, friction == nil, t >= frictionQuietUntil, blockedSites[site] != nil, !gateOpen, checkIn == nil else { return }
        if let u = passUntil[site], t < u { return }
        friction = Friction(app: w.app, siteKey: site, at: t)
        fire(.friction)
    }

    public func beginFrictionHold() { if friction != nil, frictionHoldStart == nil { frictionHoldStart = now() } }
    public func endFrictionHold() { frictionHoldStart = nil }
    /// 0 to 1 while the button is held.
    public func frictionHoldProgress() -> Double {
        guard let s = frictionHoldStart else { return 0 }
        return min(1, max(0, (now() - s) / Friction.holdSeconds))
    }
    /// Called a few times a second while the friction panel is up: finishes the hold. A short hold lets the site open for ten minutes; it is still read.
    public func updateFrictionHold() {
        guard let f = friction, frictionHoldStart != nil, frictionHoldProgress() >= 1 else { return }
        passUntil[f.siteKey] = now() + Friction.passSeconds
        friction = nil; frictionHoldStart = nil
    }
    /// A typed reason lets the site open for the rest of the session and counts as "That was fine" for the window. The words are not kept.
    @discardableResult public func submitFrictionReason(_ text: String) -> Bool {
        guard let f = friction, Friction.acceptable(reason: text) else { return false }
        passUntil[f.siteKey] = .infinity; blockedSites[f.siteKey] = nil
        friction = nil; frictionHoldStart = nil
        act(.thatWasFine)
        return true
    }
    public func frictionBackToTask() {
        friction = nil; frictionHoldStart = nil
        frictionQuietUntil = now() + 20   // give the task app time to come forward before asking again
        act(.backToTask)
    }

    // MARK: scheduled rhythm
    func tickRhythm(_ t: Double) {
        guard isActive, !shadow else { lastWorkTick = nil; return }
        let last = lastWorkTick ?? t
        lastWorkTick = t
        // Work time is the time actually spent in the session: not paused, not on a break, and a Mac that slept does not count.
        if !isPaused { workSeconds += min(max(0, t - last), 5) }
        if let p = rhythmPrompt, p.kind == .checkIn, t - p.at >= Self.checkInPromptSeconds { rhythmPrompt = nil; workSeconds = 0 }
        guard rhythmPrompt == nil, let due = prefs.rhythm.dueAfter(checkInMinutes: prefs.checkInMinutes), workSeconds >= due else { return }
        // Not while you are being warned about something else, or paused; it waits until you are working again.
        guard !isPaused, surface == nil, checkIn == nil, !gateOpen, presence.state != "interrupted", presence.state != "drifting", readings.first?.call != .off, banner == nil, friction == nil else { return }
        let kind: RhythmPrompt.Kind = prefs.rhythm == .pomodoro ? .breakDue(minutes: Rhythm.breakMinutes(afterBlock: workBlocks + 1)) : .checkIn
        rhythmPrompt = RhythmPrompt(kind: kind, at: t)
        fire(prefs.rhythm == .pomodoro ? .breakDue : .rhythmCheckIn, title: CueCopy.rhythmTitle(kind, task: taskName))
    }

    /// "Keep going". A check-in starts a new interval; a break you put off comes back in five minutes.
    public func rhythmKeepGoing() {
        guard let p = rhythmPrompt else { return }
        rhythmPrompt = nil
        if case .breakDue = p.kind, let due = prefs.rhythm.dueAfter(checkInMinutes: prefs.checkInMinutes) { workSeconds = max(0, due - 300) } else { workSeconds = 0 }
    }

    /// "Take a break": the brain pauses for the length offered, and the next block starts when the break ends.
    public func rhythmTakeBreak() {
        guard let p = rhythmPrompt else { return }
        rhythmPrompt = nil; workSeconds = 0
        switch p.kind {
        case .breakDue(let m): workBlocks += 1; act(.breakTime, minutes: m)
        case .checkIn: act(.breakTime, minutes: Rhythm.shortBreak)
        }
    }

    /// Text for the prompt's break button.
    public var rhythmBreakMinutes: Int {
        if case .breakDue(let m)? = rhythmPrompt?.kind { return m }
        return Rhythm.shortBreak
    }
}
