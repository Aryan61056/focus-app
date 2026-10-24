import ManagedSettings
import DeviceActivity

/// Names the app and its two Screen Time extensions agree on. Everything Hushd blocks lives in one named store, so clearing it
/// can never touch a restriction the person set up themselves in Settings.
enum FocusShield {
    nonisolated static var storeName: ManagedSettingsStore.Name { .init("dev.focusapp.session") }
    nonisolated static var activityName: DeviceActivityName { .init("dev.focusapp.session") }
    nonisolated static func store() -> ManagedSettingsStore { ManagedSettingsStore(named: storeName) }
}
