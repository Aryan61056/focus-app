import UserNotifications
import FocusLinkNet

/// The one honest thing a phone app can do about a phone that gets picked up mid-session. iOS lets no app see what you do in
/// other apps, so this does not catch you, and it does not claim to. It does this: if you leave Hushd while a session is
/// running on your Mac, one quiet notification follows after a short delay, naming the task and nothing else. Coming back
/// cancels it. Wording is in the past tense, because the session may have ended since.
@MainActor final class PickupReminder {
    static let identifier = "focus.pickup"
    static let delay: TimeInterval = 45
    /// At most one reminder per this long, so a phone that is picked up often is not nagged.
    static let spacing: TimeInterval = 5 * 60

    private let center = UNUserNotificationCenter.current()
    private var armedAt: Date?
    private var lastShown: Date?

    /// How long to wait before reminding, or nil when no reminder should be sent. Pure, so it can be tested.
    static func plan(clock: SessionClock, live: Bool, now: Date, lastShown: Date?) -> TimeInterval? {
        let s = clock.state
        guard live, s.isActive, s.phase != .paused, s.phase != .onBreak, !s.practice else { return nil }
        if let lastShown, now.timeIntervalSince(lastShown) < spacing { return nil }
        // A timed session about to end needs no reminder.
        if s.timed, clock.seconds(at: now.addingTimeInterval(delay)) < 60 { return nil }
        return delay
    }

    /// Ask once, at the first session, while the person is looking at the app and knows why.
    func askPermissionIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        }
    }

    func arm(clock: SessionClock, live: Bool, now: Date = .now) {
        guard let delay = Self.plan(clock: clock, live: live, now: now, lastShown: lastShown) else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Still on \(clock.state.task)?")
        content.body = String(localized: "Your session was running when you left Hushd.")
        content.interruptionLevel = .passive
        center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
        armedAt = now
        lastShown = now.addingTimeInterval(delay)
    }

    /// Back in the app: cancel it, and forget it if it never had time to show.
    func disarm(now: Date = .now) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        if let armedAt, now.timeIntervalSince(armedAt) < Self.delay { lastShown = nil }
        armedAt = nil
    }
}
