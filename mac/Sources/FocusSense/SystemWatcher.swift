import AppKit
import CoreGraphics
import FocusBrain
import FocusUI

/// While a session runs, tells the brain about the computer itself: a call (camera or microphone in use), no keyboard or mouse for a while (Idle and Active), the lid closing or
/// the screen locking (Sleep and Wake), and Low Power Mode or heat (PowerChange, which makes the brain check less often).
/// None of it needs a permission, and none of it reads a window. The brain decides what to do (pause the clock, ask to resume).
@MainActor
public final class SystemWatcher {
    private let controller: SessionController
    private let idleSeconds: () -> Double
    private let powerState: () -> (constrained: Bool, critical: Bool)
    private let threshold: Double
    private let inCall: () -> Bool
    private var callPolls = 0
    private var inMeeting = false
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var idle = false
    private var asleep = false
    private var lastPower: (Bool, Bool) = (false, false)

    public init(controller: SessionController, idleThreshold: Double = 240,
                idleSeconds: @escaping () -> Double = { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) },
                inCall: @escaping () -> Bool = { CallDetector.inCall() },
                powerState: @escaping () -> (constrained: Bool, critical: Bool) = {
                    let p = ProcessInfo.processInfo
                    return (p.isLowPowerModeEnabled || p.thermalState == .serious || p.thermalState == .critical, p.thermalState == .critical)
                }) {
        self.controller = controller; self.idleSeconds = idleSeconds; self.powerState = powerState; self.threshold = idleThreshold; self.inCall = inCall
    }

    public var isRunning: Bool { timer != nil }

    public func start(interval: TimeInterval = 5) {
        guard timer == nil else { return }
        idle = false; asleep = false; lastPower = (false, false); callPolls = 0; inMeeting = false
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        let ws = NSWorkspace.shared.notificationCenter, dc = DistributedNotificationCenter.default()
        func on(_ c: NotificationCenter, _ n: Notification.Name, _ f: @escaping @MainActor (SystemWatcher) -> Void) {
            observers.append((c, c.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { if let s = self { f(s) } } }))
        }
        on(ws, NSWorkspace.willSleepNotification) { $0.sleepChanged(true) }
        on(ws, NSWorkspace.didWakeNotification) { $0.sleepChanged(false) }
        on(ws, NSWorkspace.screensDidSleepNotification) { $0.sleepChanged(true) }
        on(ws, NSWorkspace.screensDidWakeNotification) { $0.sleepChanged(false) }
        on(dc, Notification.Name("com.apple.screenIsLocked")) { $0.sleepChanged(true) }
        on(dc, Notification.Name("com.apple.screenIsUnlocked")) { $0.sleepChanged(false) }
        on(.default, .NSProcessInfoPowerStateDidChange) { $0.poll() }
        on(.default, ProcessInfo.thermalStateDidChangeNotification) { $0.poll() }
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        for (c, o) in observers { c.removeObserver(o) }
        observers = []
    }

    /// Exposed so tests can drive it without a timer.
    public func poll() {
        let p = powerState()
        if (p.constrained, p.critical) != lastPower { lastPower = (p.constrained, p.critical); controller.send(.powerChange(constrained: p.constrained, critical: p.critical)) }
        guard !asleep else { return }
        // A call needs two polls in a row (about 10 s) so a notification sound or a quick voice memo does not pause the session.
        callPolls = inCall() ? callPolls + 1 : 0
        if !inMeeting && callPolls >= 2 { inMeeting = true; controller.send(.meetingStart) }
        else if inMeeting && callPolls == 0 { inMeeting = false; controller.send(.meetingEnd) }
        let isIdle = idleSeconds() >= threshold
        if isIdle != idle { idle = isIdle; controller.send(isIdle ? .idle : .active) }
    }

    func sleepChanged(_ on: Bool) {
        guard on != asleep else { return }
        asleep = on
        controller.send(on ? .sleep : .wake)
        if !on { idle = false }   // waking is input; the next poll re-checks the real idle time
    }
}
