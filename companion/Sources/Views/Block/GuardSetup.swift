import SwiftUI

/// iOS lets an app offer an action to Shortcuts but not create the automation for you, so this is the one setup the person does,
/// once. "Hushd" is also the name of iOS's Do Not Disturb modes, which Siri readily mixes up with this app, so the action is called
/// "Guard my session", the request says what it is not, and the page shows whether the automation has ever actually run.
struct GuardSetup: View {
    @Environment(AppModel.self) private var model
    @State private var checking = false
    @State private var copied = 0

    private static let action = "Guard my session"

    private var prompt: String {
        let apps = SocialApps.suggestions.dropLast().joined(separator: ", ") + " or " + (SocialApps.suggestions.last ?? "Pinterest")
        return "Create a personal automation with the trigger App: when \(apps) is opened, run immediately without asking. The only action is the app action \"\(Self.action)\" from the app named Hushd (a green ring icon). It is not an iOS Focus mode, so do not use Set Focus or Do Not Disturb, and do not add Open App."
    }

    var body: some View {
        @Bindable var blocker = model.blocker
        Section {
            Toggle(isOn: $blocker.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Guard while I focus")
                    Text("Opening a social app during a session brings you back here.").font(.footnote).foregroundStyle(Palette.ink2)
                }
            }
            .tint(Palette.accent)
        } header: { Text("App guard") } footer: { lastRun }

        Section {
            step(1, "Open Shortcuts, tap Automation, then + and tap the sparkle button.")
            step(2, "Paste the request below, or tap Copy request first.")
            step(3, "Before you save, check the action is \"\(Self.action)\" with the green ring. Delete Open App, Set Focus or anything else.")
            Text(prompt).font(.footnote).foregroundStyle(Palette.ink2).textSelection(.enabled)
            Button { UIPasteboard.general.string = prompt; copied += 1 } label: { Label("Copy request", systemImage: "doc.on.doc") }
            Button { open("shortcuts://") } label: { Label("Open Shortcuts", systemImage: "arrow.up.forward.app") }
        } header: { Text("Set up with Siri") } footer: {
            Text("Siri sometimes picks Open App or an iOS Focus mode because they sound alike. Those ignore the switch above and always open this app.")
        }
        .successFeedback(copied)

        Section {
            step(1, "Tap Automation, then +, then App.")
            step(2, "Choose your social apps, set Is Opened and Run Immediately, then tap Next.")
            step(3, "Tap Add Action, search for \"\(Self.action)\" (not Hushd), choose it, then tap Done.")
        } header: { Text("Or build it yourself") }

        Section {
            Button { Task { await tryIt() } } label: { Label("Check it works", systemImage: "play.circle") }.disabled(checking)
        } footer: {
            Text(model.notice ?? "Run this with a session going on your Mac to see where it sends you.")
        }
    }

    /// Shown under the switch: proof the automation is wired up, or a plain note that it has not run yet.
    @ViewBuilder private var lastRun: some View {
        if let last = model.lastGuard {
            Text("Last ran \(last.at.formatted(.relative(presentation: .named))): \(last.outcome.sentence).")
        } else {
            Text("The automation hasn't run yet. After you set it up, open a social app once and this line will say what happened.")
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "\(n).circle.fill").foregroundStyle(Palette.accent).font(.title3).symbolRenderingMode(.hierarchical)
            Text(text).font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    private func open(_ s: String) { if let u = URL(string: s) { UIApplication.shared.open(u) } }

    private func tryIt() async {
        checking = true; defer { checking = false }
        let outcome = await model.guardCheck(record: false)
        if outcome.bounces { model.showGuard() } else { model.show(String(localized: "Right now: \(outcome.sentence).")) }
    }
}
