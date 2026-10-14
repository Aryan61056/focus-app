import AppIntents

/// The one action behind the guard. It is meant to run from a Shortcuts automation ("When Instagram is opened"). If a session
/// is working it brings Focus forward; if not, it does nothing at all, so the social app opens as if Focus were not there.
struct GuardFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Guard my session"
    static let description = IntentDescription("Sends you back to your work session if one is running, and does nothing otherwise. Run it when a distracting app opens. This is not an iOS Focus mode.")
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = AppModel.shared
        if await model.guardCheck().bounces {
            model.showGuard()
            try await continueInForeground(alwaysConfirm: false)
        }
        return .result()
    }
}

/// Makes the action appear in Shortcuts by itself, with nothing to install or import.
struct FocusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GuardFocusIntent(), phrases: ["Guard my session with \(.applicationName)"], shortTitle: "Guard my session", systemImageName: "shield.lefthalf.filled")
    }
}
