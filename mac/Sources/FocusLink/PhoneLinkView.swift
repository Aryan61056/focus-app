import SwiftUI
import FocusUI
import FocusLinkNet

/// The iPhone window: turn the link on, pair a phone with a code, see and remove phones.
public struct PhoneLinkView: View {
    let link: PhoneLink
    public init(link: PhoneLink) { self.link = link }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("iPhone").font(Tokens.rounded(20)).foregroundStyle(Tokens.ink)
                Text("See this session on your phone, and start, pause or end it from there.").font(Tokens.text(13)).foregroundStyle(Tokens.ink2)
            }
            Toggle("Let a paired phone connect", isOn: Binding(get: { link.enabled }, set: { link.setEnabled($0) }))
                .toggleStyle(.switch).font(Tokens.text(13, .medium))

            if link.enabled {
                Divider()
                if let code = link.pairingCode { pairing(code) }
                else { Button { link.beginPairing() } label: { Label("Pair a phone", systemImage: "iphone.badge.plus") }.buttonStyle(FocusButtonStyle(.primary)) }
                phones
            }
            if let e = link.lastError { Text(e).font(Tokens.text(12)).foregroundStyle(Tokens.ink2) }
            Spacer(minLength: 0)
            Text("Your phone talks to this Mac directly over your Wi-Fi. There is no account and no server of ours in between. Turn the switch off and Focus stops listening.")
                .font(Tokens.text(11.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(22).frame(width: 420, height: 440, alignment: .topLeading).background(Tokens.window)
    }

    private func pairing(_ code: PairingCode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On your iPhone, open Focus, choose Add your Mac, and type:").font(Tokens.text(13)).foregroundStyle(Tokens.ink2)
            Text(code.display).font(.system(size: 26, weight: .semibold, design: .monospaced)).foregroundStyle(Tokens.ink).textSelection(.enabled)
                .padding(.vertical, 12).padding(.horizontal, 16).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Tokens.radiusCard).fill(Tokens.accentSoft))
            HStack {
                Text("Works for five minutes, for one phone.").font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
                Spacer()
                Button("Cancel") { link.cancelPairing() }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        }
    }

    @ViewBuilder private var phones: some View {
        if !link.phones.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paired phones").font(Tokens.text(12, .semibold)).foregroundStyle(Tokens.ink2)
                ForEach(link.phones) { phone in
                    HStack(spacing: 10) {
                        Circle().fill(link.connected.contains { $0.id == phone.id } ? Tokens.accent : Tokens.track).frame(width: 8, height: 8)
                        Text(phone.name).font(Tokens.text(13, .medium)).foregroundStyle(Tokens.ink)
                        Text(link.connected.contains { $0.id == phone.id } ? "Connected" : "Not connected").font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
                        Spacer()
                        Button("Remove") { link.remove(phone.id) }.buttonStyle(FocusButtonStyle(.plain, small: true))
                    }
                }
            }
        }
    }
}
