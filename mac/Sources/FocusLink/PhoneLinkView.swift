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
            Text("Your phone talks to this Mac directly over your Wi-Fi. There is no account and no server of ours in between. Turn the switch off and Focus stops listening.")
                .font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(22).frame(width: 440, height: 560, alignment: .topLeading).background(Tokens.window)
        .animation(.smooth(duration: 0.3), value: link.pairingCode)
        .animation(.smooth(duration: 0.3), value: link.justPaired)
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 16) {
            phones
            Button { link.beginPairing() } label: { Label(link.phones.isEmpty ? "Pair an iPhone" : "Pair another iPhone", systemImage: "iphone.badge.plus").frame(maxWidth: .infinity) }
                .buttonStyle(FocusButtonStyle(.primary, expand: true))
            Text("Install Focus on your iPhone first, then press the button. It takes about ten seconds.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        }
    }

    private func pairingBox(_ pairing: PairingLink) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Point your iPhone's Camera at this, then tap the banner that appears.").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
            HStack {
                Spacer()
                if let qr = QRCode.image(for: pairing.url.absoluteString, points: 190) {
                    Image(nsImage: qr).interpolation(.none).resizable().frame(width: 190, height: 190)
                        .padding(14).background(RoundedRectangle(cornerRadius: Tokens.radiusCard).fill(.white))
                        .accessibilityLabel("QR code for pairing your iPhone")
                }
                Spacer()
            }
            Text("Or open Focus on your iPhone, choose Add your Mac, and type:").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
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
