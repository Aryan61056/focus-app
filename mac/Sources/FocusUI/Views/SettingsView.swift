import SwiftUI
import FocusBrain
import AppKit

struct SettingsView: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    @State private var confirmDelete = false
    @State private var skip = true
    var body: some View {
        Scroller {
            VStack(alignment: .leading, spacing: 26) {
                Text("Settings").font(Tokens.rounded(26, .semibold))
                group("Nudges") {
                    HStack(spacing: 10) {
                        opt(.gentle, "Gentle", "One quiet note after about three minutes.")
                        opt(.standard, "Standard", "A card after about a minute, again every five.")
                        opt(.strict, "Strict", "A pause screen after 45 seconds.")
                    }.padding(14)
                    row("Practice mode", "Watch without interrupting for the first \(Preferences.practiceSessions) sessions.") {
                        Toggle("", isOn: Binding(get: { c.prefs.practiceActive }, set: { $0 ? c.prefs.restartPractice() : c.prefs.turnNudgesOnNow() })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                }
                group("What Focus looks at") {
                    row("Window titles and text", "The app name, the title, the page address and the words in the window.") { Text("On").foregroundStyle(Tokens.ink2) }
                    row("Skip personal messages, music and blank pages", "Focus leaves these alone: it does not read them and does not count them as off topic.") {
                        Toggle("", isOn: $skip).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    if skip {
                        RuleGroup(title: "Apps", symbol: "app", items: Binding(get: { c.prefs.neverJudgedApps }, set: { c.prefs.neverJudgedApps = $0 }), addLabel: "Add app")
                            .padding(.horizontal, 16).padding(.bottom, 10).overlay(alignment: .top) { Divider().overlay(Tokens.line) }
                    }
                    row("Never looked at", "Password managers, banking sites and private windows are skipped, always.") { Label("Always on", systemImage: "lock").foregroundStyle(Tokens.ink2) }
                }
                group("Privacy") {
                    row("Where the work happens", "The judge is Apple's on-device model. There is no account.") { Text("On this Mac").foregroundStyle(Tokens.ink2) }
                    row("Your data", "\(store.projects.count) projects, \(store.sessions.count) sessions and \(store.review.count) review moments.") {
                        HStack {
                            Button("Export") { export() }.buttonStyle(FocusButtonStyle(.plain, small: true))
                            Button("Delete everything") { confirmDelete = true }.buttonStyle(FocusButtonStyle(.plain, small: true))
                        }
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
        }
        .onAppear { skip = c.prefs.skipPersonal }
        .onChange(of: skip) { _, v in c.prefs.skipPersonal = v }
        .confirmationDialog("Delete everything?", isPresented: $confirmDelete) {
            Button("Delete everything", role: .destructive) { store.deleteEverything() }
        } message: { Text("Projects, sessions, rules and review moments are removed from this Mac. This cannot be undone.") }
    }

    func opt(_ p: Preset, _ title: String, _ text: String) -> some View {
        let on = c.prefs.preset == p
        return Button { c.prefs.preset = p } label: {
            VStack(alignment: .leading, spacing: 4) { Text(title).font(Tokens.text(13.5, .semibold)); Text(text).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true) }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(on ? Tokens.accentSoft : Tokens.control))
                .overlay { if on { RoundedRectangle(cornerRadius: 12).strokeBorder(Tokens.accent, lineWidth: 1.5) } }
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    func group<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title)
            VStack(spacing: 0) { content() }.overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Tokens.line) }
        }
    }

    func row<V: View>(_ title: String, _ help: String, @ViewBuilder _ trailing: () -> V) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) { Text(title).font(Tokens.text(13.5, .semibold)); Text(help).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
            Spacer(); trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 12).overlay(alignment: .top) { Divider().overlay(Tokens.line) }
    }

    func export() {
        guard let data = store.exportJSON() else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "focus-data.json"
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
    }
}
