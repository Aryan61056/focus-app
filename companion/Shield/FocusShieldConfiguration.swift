import ManagedSettings
import ManagedSettingsUI
import UIKit

/// What a blocked app shows. Plain and calm, and it says when the app comes back, because "Restricted" alone feels like a bug.
nonisolated final class FocusShieldConfiguration: ShieldConfigurationDataSource {
    private var shield: ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: nil,
            icon: UIImage(systemName: "leaf.fill"),
            title: .init(text: "Hushd is on", color: .label),
            subtitle: .init(text: "You chose to keep this closed while you work. It opens on a break, when you pause, or when the session ends.", color: .secondaryLabel)
        )
    }
    override func configuration(shielding application: Application) -> ShieldConfiguration { shield }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { shield }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { shield }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { shield }
}
