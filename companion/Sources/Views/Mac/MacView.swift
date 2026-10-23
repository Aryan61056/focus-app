import SwiftUI

struct MacView: View {
    @Environment(AppModel.self) private var model
    @State private var showPairing = false
    @State private var confirmForget = false

    private var title: LocalizedStringKey {
        switch model.connection {
        case .connected, .connecting, .searching, .offline: "Your Mac"
        case .demo: "Demo mode"
        case .unpaired: "No Mac yet"
        }
    }
    private var subtitle: String {
        switch model.connection {
        case .connected: String(localized: "Connected to \(model.mac?.macName ?? "your Mac")")
        case .connecting: String(localized: "Connecting to \(model.mac?.macName ?? "your Mac")")
        case .searching: String(localized: "Looking for \(model.mac?.macName ?? "your Mac") on this Wi-Fi")
        case .offline(let why): why ?? String(localized: "Can't reach your Mac")
        case .demo: String(localized: "A pretend Mac, so you can look around")
        case .unpaired: String(localized: "Pair this phone with the Hushd app on your Mac")
        }
    }

    private var iCloudLine: String {
        switch model.cloud.status {
        case .idle, .checking: model.cloud.snapshot.map { String(localized: "Insights from \($0.asOf.formatted(.relative(presentation: .named)))") } ?? String(localized: "Checking iCloud\u{2026}")
        case .unavailable(let why), .failed(let why): why
        case .ready: model.cloud.snapshot.map { String(localized: "Insights updated \($0.asOf.formatted(.relative(presentation: .named)))") } ?? String(localized: "Your Mac hasn't shared Insights yet")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "macbook").font(.title).foregroundStyle(model.connection.isLive ? Palette.accent : Palette.ink2).symbolRenderingMode(.hierarchical)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.headline)
                            Text(subtitle).font(.subheadline).foregroundStyle(Palette.ink2)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    if model.connection == .unpaired { Button("Add your Mac") { showPairing = true } }
                    if model.mac != nil { Button("Forget this Mac", role: .destructive) { confirmForget = true } }
                }
                Section {
                    Label(iCloudLine, systemImage: "icloud").foregroundStyle(Palette.ink2)
                } header: { Text("iCloud") } footer: {
                    Text("Turn on Keep Insights in iCloud in the Mac app's iPhone window. Your days and sessions then show here when the Mac is off or away. Only times, counts and the task names you typed are stored, in your own iCloud.")
                }
                Section {
                    Toggle("Demo mode", isOn: Binding(get: { model.isDemo }, set: { $0 ? model.startDemo() : model.stopDemo() }))
                        .tint(Palette.accent)
                } footer: { Text("Explore the app with a pretend Mac. Nothing is sent anywhere.") }
                Section("How it keeps you honest") {
                    Label("Your session stays on the lock screen, so the task is the first thing you see when you pick up your phone.", systemImage: "lock.iphone")
                    Label("Start, pause or end a session from here, without opening your Mac.", systemImage: "hand.tap")
                }
                .font(.subheadline).foregroundStyle(Palette.ink2)
                Section {} footer: {
                    Text("Live sessions go directly between your phone and Mac over your Wi-Fi. There's no account and no server of ours in between.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationTitle("Mac")
        }
        .sheet(isPresented: $showPairing) { PairingView() }
        .confirmationDialog("Forget this Mac?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget Mac", role: .destructive) { model.forgetMac() }
        } message: { Text("You can pair again any time from the Mac.") }
    }
}
