import SwiftUI
import FocusUI
import FocusLinkNet

/// The iPhone window. One button does everything: turn the link on, open pairing and show the code to scan or type.
public struct PhoneLinkView: View {
    let link: PhoneLink
    public init(link: PhoneLink) { self.link = link }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("iPhone").font(Tokens.rounded(.title3)).foregroundStyle(Tokens.ink)
                Text("See this session on your phone, and start, pause or end it from there.").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
            }
            Group {
                if let paired = link.justPaired { success(paired) }
                else if let pairing = link.pairingLink { pairingBox(pairing) }
                else { idle }
            }
            .transition(.opacity)
            if let e = link.lastError { Text(e).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
            Spacer(minLength: 0)
            if link.enabled {
                Divider()
                HStack {
                    Toggle("Let paired phones connect", isOn: Binding(get: { link.enabled }, set: { link.setEnabled($0) })).toggleStyle(.switch).font(Tokens.text(.caption))
                }
            }
            Divider()
            iCloudRow
            Text("Your phone talks to this Mac directly over your Wi-Fi. There is no account and no server of ours in between. Turn the switch off and Hushd stops listening.")
                .font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(22).frame(width: 440, height: 560, alignment: .topLeading).background(Tokens.window)
        .animation(.smooth(duration: 0.3), value: link.pairingCode)
        .animation(.smooth(duration: 0.3), value: link.justPaired)
    }

    /// The phone's Insights through the person's own iCloud. Says exactly what is stored, because it is the one place these numbers leave the Mac.
    private var iCloudRow: some View {
        let sync = link.sync
        return VStack(alignment: .leading, spacing: 4) {
            Toggle("Keep Insights in iCloud", isOn: Binding(get: { sync.enabled }, set: { on in Task { await sync.setEnabled(on) } }))
                .toggleStyle(.switch).font(Tokens.text(.caption))
            Group {
                switch sync.status {
                case .off: Text("Your phone shows your days and sessions anywhere. Stored: times, counts and the task names you typed, in your own iCloud, readable only by your devices. Never windows or screen text.")
                case .checking: Text("Checking iCloud\u{2026}")
                case .ready(let at): Text("Up to date, \(at.formatted(date: .omitted, time: .shortened)).")
                case .unavailable(let why), .failed(let why): Text(why)
                }
            }
            .font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var idle: some View {
        let installer = link.installer
        // While Hushd is offering to install the app, that is the step in front of you and pairing waits its turn.
        let installing: Bool = {
            switch installer.state { case .ready, .installing, .building, .needsXcodegen, .installingXcodegen, .needsTeam: return true; default: return false }
        }()
        return VStack(alignment: .leading, spacing: 16) {
            phones
            installBlock(installer)
            Button { link.beginPairing() } label: { Label(link.phones.isEmpty ? "Pair an iPhone" : "Pair another iPhone", systemImage: "iphone").frame(maxWidth: .infinity) }
                .buttonStyle(FocusButtonStyle(installing ? .secondary : .primary, expand: true))
            Text(installer.state == .notIncluded ? "Install Hushd on your iPhone first, then press the button. It takes about ten seconds."
                                                  : "Open Hushd on your iPhone, then press the button. It takes about ten seconds.")
                .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        }
        // Looks for a plugged-in iPhone while this step is on screen, so plugging one in is noticed.
        .task { await installer.watch() }
    }

    /// Step one: get the app onto the phone. Shown only when this copy of Hushd carries an iPhone build.
    @ViewBuilder private func installBlock(_ installer: PhoneInstaller) -> some View {
        if installer.state != .notIncluded {
            VStack(alignment: .leading, spacing: 10) {
                Text("Put Hushd on your iPhone").font(Tokens.text(.callout, .semibold)).foregroundStyle(Tokens.ink)
                switch installer.state {
                case .notIncluded: EmptyView()
                case .idle, .looking:
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking for your iPhone\u{2026}").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
                case .needsXcode:
                    Text("Installing from here needs Xcode on this Mac.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                case .noPhone:
                    Text("Plug in your iPhone with a cable, unlock it and tap Trust. It appears here.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                case .ready(let targets):
                    ForEach(targets) { target in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Image(systemName: "iphone").foregroundStyle(Tokens.accentInk)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(target.name).font(Tokens.text(.body, .medium)).foregroundStyle(Tokens.ink).lineLimit(1)
                                    if !target.model.isEmpty { Text(target.model).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
                                }
                                Spacer()
                                Button(installer.buildsItself ? "Build and install" : "Install Hushd") { Task { await installer.install(on: target) } }.buttonStyle(FocusButtonStyle(.primary, small: true))
                                    .help(installer.buildsItself ? "Hushd makes the iPhone app on this Mac, signs it with your Apple ID's team and puts it on the phone." : "Puts the iPhone app on this phone over the cable.")
                            }
                            if target.needsDeveloperMode {
                                Text("Turn on Developer Mode on this iPhone first: Settings, Privacy & Security.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case .installing(let name):
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Installing on \(name). Keep it unlocked.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
                case .building(let phone, let step):
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(step).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true) }
                        Text("Keep \(phone) plugged in and unlocked.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                    }
                case .needsXcodegen:
                    Text("Hushd needs a small free tool, xcodegen, to build the iPhone app. It installs with Homebrew.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Install xcodegen") { Task { await installer.installXcodegen() } }.buttonStyle(FocusButtonStyle(.primary, small: true))
                        Button("Not now") { Task { await installer.again() } }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                case .installingXcodegen:
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Installing xcodegen\u{2026}").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
                case .needsTeam:
                    TeamEntry(installer: installer)
                case .installed(let name):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.accent)
                        Text("Hushd is on \(name). Open it there, then pair below.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .failed(let message):
                    Text(message).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await installer.again() } }.buttonStyle(FocusButtonStyle(.plain, small: true))
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusCard).fill(Tokens.well))
            .animation(.smooth(duration: 0.25), value: installer.state)
        }
    }

    private func pairingBox(_ pairing: PairingLink) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Point your iPhone's Camera at this, then tap the banner that appears.").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
            HStack {
                Spacer()
                // A tree to tap; tapping it turns it into the code (PairingGarden.swift). The code is drawn in memory and never saved.
                PairingGarden(url: pairing.url.absoluteString)
                Spacer()
            }
            Text("Or open Hushd on your iPhone, choose Add your Mac, and type:").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
            Text(pairing.code.display).font(.system(size: 22, weight: .semibold, design: .monospaced)).foregroundStyle(Tokens.ink).textSelection(.enabled)
                .padding(.vertical, 10).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: Tokens.radiusCard).fill(Tokens.accentSoft))
            HStack {
                Text("Works for five minutes, then it stops.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                Spacer()
                Button("Cancel") { link.cancelPairing() }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        }
    }

    private func success(_ phone: PairedDevice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(Tokens.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(phone.name) is paired").font(Tokens.text(.callout, .semibold)).foregroundStyle(Tokens.ink)
                    Text("Start a session on either device and you'll see it on both.").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                }
            }
            Button("Done") { link.dismissPaired() }.buttonStyle(FocusButtonStyle(.secondary))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.radiusCard).fill(Tokens.accentSoft))
    }

    @ViewBuilder private var phones: some View {
        if !link.phones.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paired phones").font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink2)
                ForEach(link.phones) { phone in
                    let on = link.connected.contains { $0.id == phone.id }
                    HStack(spacing: 10) {
                        Circle().fill(on ? Tokens.accent : Tokens.track).frame(width: 8, height: 8)
                        Text(phone.name).font(Tokens.text(.body, .medium)).foregroundStyle(Tokens.ink)
                        Text(on ? "Connected" : (link.enabled ? "Not connected" : "Link is off")).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                        Spacer()
                        Button("Remove") { link.remove(phone.id) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                }
            }
        }
    }
}


/// Shown only when Xcode has no signed-in Apple ID to take a team from: sign in there (Hushd then finds it), or type the ten characters.
private struct TeamEntry: View {
    var installer: PhoneInstaller
    @State private var team = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hushd signs the iPhone app with your Apple ID. Sign in under Xcode, Settings, Accounts and try again, or paste your 10-character team id.")
                .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("Team id", text: $team).textFieldStyle(.roundedBorder).frame(maxWidth: 160).onSubmit(use)
                Button("Use it", action: use).buttonStyle(FocusButtonStyle(.primary, small: true)).disabled(!PhoneBuild.isTeamID(team.trimmingCharacters(in: .whitespaces)))
                Button("Try again") { Task { await installer.again() } }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        }
    }
    private func use() { Task { await installer.useTeam(team) } }
}
