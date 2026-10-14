import DeviceActivity

/// The safety net. The app is asleep when a session ends on the Mac, so it cannot lift the block itself; iOS wakes this instead,
/// at the end time the app scheduled. A block therefore always ends, even if the phone never hears from the Mac again.
nonisolated final class FocusMonitor: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == FocusShield.activityName { FocusShield.store().clearAllSettings() }
    }
}
