import SwiftUI
import FamilyControls
import ManagedSettings

/// Pick the apps and sites that pull you away. They are covered while a session is running and open again on a break.
struct BlockView: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var confirmLift = false

    var body: some View {
        @Bindable var blocker = model.blocker
        NavigationStack {
            List {
                GuardSetup()
                statusSection
                if !blocker.isAuthorized {
                    accessSection
                } else {
                    chosenSection
                    Section {} footer: { Text("Covered while you're working. Open again when you pause, take a break, or the session ends.") }
                }
                Section {} footer: {
                    Text("This is a promise to yourself, not a lock. You can lift it here or in Settings › Screen Time. Hushd can't see which apps you picked; only iOS knows.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationTitle("Block")
        }
        .familyActivityPicker(headerText: "Pick what pulls you away", footerText: "Apps, categories and websites.", isPresented: $picking, selection: $blocker.selection)
        .confirmationDialog("Open your apps now?", isPresented: $confirmLift, titleVisibility: .visible) {
            Button("Open them", role: .destructive) { blocker.unblockNow() }
            Button("Keep them covered", role: .cancel) {}
        } message: { Text("They stay open until your next session starts.") }
        .task { blocker.refreshAccess() }
    }

    // MARK: sections
    private var statusSection: some View {
        let b = model.blocker
        return Section {
            HStack(spacing: 14) {
                Image(systemName: b.shielding ? "shield.lefthalf.filled.badge.checkmark" : "shield")
                    .font(.title).foregroundStyle(b.shielding ? Palette.accent : Palette.ink2)
                    .symbolRenderingMode(.hierarchical).contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(Palette.ink2)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            if b.shielding { Button("Open my apps now", role: .destructive) { confirmLift = true } }
        } header: { Text("Full blocking") } footer: {
            if !b.isAuthorized { Text("Covers the apps themselves so they can't open at all. Needs an Apple Developer Program account.") }
        }
        .motion(Motion.settle, value: b.shielding)
    }

    private var headline: LocalizedStringKey {
        let b = model.blocker
        if b.shielding { return "Covered right now" }
        if !b.isAuthorized { return "Not set up" }
        return b.hasSelection ? "Ready to cover \(b.count)" : "Nothing chosen yet"
    }

    private var detail: LocalizedStringKey {
        let b = model.blocker
        if b.shielding { return "They open again on a break or when the session ends." }
        if !b.isAuthorized { return "Allow Screen Time access to choose what to cover." }
        return b.hasSelection ? "They'll be covered the next time a session is running." : "Choose the apps and sites that pull you away."
    }

    @ViewBuilder private var accessSection: some View {
        let b = model.blocker
        Section {
            switch b.access {
            case .denied:
                Text("Screen Time access is off for Hushd. Turn it on in Settings › Screen Time to choose what to cover.")
                    .font(.subheadline).foregroundStyle(Palette.ink2)
                Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
            case .unavailable(let why):
                Text(why).font(.subheadline).foregroundStyle(Palette.ink2)
                Button("Try again") { Task { await b.requestAccess() } }
            default:
                Text("Hushd uses Apple's Screen Time to cover the apps you pick. What you pick stays on this phone.")
                    .font(.subheadline).foregroundStyle(Palette.ink2)
                Button { Task { await b.requestAccess() } } label: {
                    Label("Allow Screen Time access", systemImage: "hand.raised")
                }
                .disabled(b.asking)
            }
        }
    }

    @ViewBuilder private var chosenSection: some View {
        @Bindable var blocker = model.blocker
        Section {
            Button { picking = true } label: {
                Label(blocker.hasSelection ? "Change what's covered" : "Choose what to cover", systemImage: "plus.app")
            }
            ForEach(Array(blocker.selection.applicationTokens), id: \.self) { token in
                Label(token).labelStyle(.titleAndIcon)
                    .swipeActions { Button("Remove", role: .destructive) { blocker.selection.applicationTokens.remove(token) } }
            }
            ForEach(Array(blocker.selection.categoryTokens), id: \.self) { token in
                Label(token).labelStyle(.titleAndIcon)
                    .swipeActions { Button("Remove", role: .destructive) { blocker.selection.categoryTokens.remove(token) } }
            }
            ForEach(Array(blocker.selection.webDomainTokens), id: \.self) { token in
                Label(token).labelStyle(.titleAndIcon)
                    .swipeActions { Button("Remove", role: .destructive) { blocker.selection.webDomainTokens.remove(token) } }
            }
        } header: { if blocker.hasSelection { Text("Covered while you focus") } }
    }
}
