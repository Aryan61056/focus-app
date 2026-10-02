import SwiftUI
import FocusBrain
import AppKit

struct SettingsView: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    @State private var confirmDelete = false
    var probeBusy: Bool { if case .waiting = c.probe { return true }; return false }
    var probeText: String {
        switch c.probe {
        case .idle: return "Switch to another window after pressing the button. Focus tells you what it can see there. Nothing is kept."
        case .waiting(let n): return "Switch to the window you want to test. Reading in \(n)."
        case .nothing: return "Focus itself was in front, so nothing was read. Try again and switch to another app before the countdown ends."
        case .saw(let app, let title, let trusted):
            if !trusted { return "Saw the app \u{201C}\(app)\u{201D} only. Allow Accessibility to see window titles." }
            return title.isEmpty ? "Saw the app \u{201C}\(app)\u{201D}, but that window gave no title." : "Saw \u{201C}\(app)\u{201D}, window \u{201C}\(title)\u{201D}."
        }
    }
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
                    row("Window titles", "The app name, the window title and the page or file address, from the window in front.") { Text("On").foregroundStyle(Tokens.ink2) }
                    row("Window access", c.windowAccess == .allowed ? "Accessibility is allowed, so Focus can read window titles." : "Without Accessibility, Focus can only see which app is in front. Allow it in System Settings, then come back.") {
                        if c.windowAccess == .allowed { Label("Allowed", systemImage: "checkmark").foregroundStyle(Tokens.ink2) }
                        else { Button("Open Accessibility settings") { c.onOpenAccessSettings?() }.buttonStyle(FocusButtonStyle(.secondary, small: true)) }
                    }
                    row("Try it", probeText) {
                        Button(probeBusy ? "Switch windows now" : "Check in 5 seconds") { c.runProbe() }.buttonStyle(FocusButtonStyle(.secondary, small: true)).disabled(probeBusy)
                    }
                    row("Skip personal messages, music and blank pages", "Focus leaves these alone: it does not read them and does not count them as off topic.") {
                        Toggle("", isOn: Binding(get: { c.prefs.skipPersonal }, set: { c.prefs.skipPersonal = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    if c.prefs.skipPersonal {
                        RuleGroup(title: "Apps", symbol: "app", items: Binding(get: { c.prefs.neverJudgedApps }, set: { c.prefs.neverJudgedApps = $0 }), addLabel: "Add app")
                            .padding(.horizontal, 16).padding(.bottom, 10).overlay(alignment: .top) { Divider().overlay(Tokens.line) }
                    }
                    row("Never looked at", "Password managers, banking sites and private windows are skipped, always.") { Label("Always on", systemImage: "lock").foregroundStyle(Tokens.ink2) }
                }
                group("Appearance") {
                    row("Show in the notch", "A ring and the time while a session runs. On a Mac without a notch it is a small pill under the menu bar.") {
                        Toggle("", isOn: Binding(get: { c.prefs.showNotch }, set: { c.prefs.showNotch = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                }
                group("Shortcut") {
                    row("Start or pause from anywhere", "Press Control, Option and F. With no session it opens the start sheet on the project you worked on last. During a session it pauses or resumes.") {
                        Text("\u{2303}\u{2325}F").font(Tokens.rounded(14, .semibold)).foregroundStyle(Tokens.ink2)
                    }
                }
                group("Screen reading") {
                    row("Read the words on screen", "While a session runs, Focus takes a picture of the window every few seconds, reads the words on it on this Mac, and shows you the picture on Today. The model gets the words, not the picture. Needs Screen Recording. Nothing is saved. Private and never-judged windows are skipped.") {
                        Toggle("", isOn: Binding(get: { c.prefs.readScreen }, set: { c.prefs.readScreen = $0; if $0 { c.onRequestPreviewAccess?() } })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    if c.prefs.readScreen {
                        row("Screen Recording", c.previewAccess == .allowed ? "Allowed. If the picture does not appear, quit and reopen Focus once." : "Not allowed yet. Allow Focus in System Settings, then quit and reopen it. If Focus is already switched on, remove it with the minus button and add it again.") {
                            if c.previewAccess == .allowed { Label("Allowed", systemImage: "checkmark").foregroundStyle(Tokens.ink2) }
                            else { Button("Open Screen Recording settings") { c.onRequestPreviewAccess?() }.buttonStyle(FocusButtonStyle(.secondary, small: true)) }
                        }
                    }
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
            VStack(alignment: .leading, spacing: 2) { Text(title).font(Tokens.text(13.5, .semibold)); Text(help).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 12); trailing().fixedSize().layoutPriority(2)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).overlay(alignment: .top) { Divider().overlay(Tokens.line) }
    }

    func export() {
        guard let data = store.exportJSON() else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "focus-data.json"
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
    }
}
