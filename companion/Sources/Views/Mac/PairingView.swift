import SwiftUI
import FocusLinkNet

/// Pairing in two steps the person can do without reading: pick the Mac, type the code it shows.
struct PairingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selected: LinkClient.FoundMac?
    @State private var code = ""
    @State private var working = false
    @State private var problem: String?
    @State private var paired = 0
    @FocusState private var codeFocused: Bool

    private var found: [LinkClient.FoundMac] { model.client.found }
    private var ready: Bool { (selected ?? found.first) != nil && PairingCode(entered: code) != nil && !working }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    step(1, "On your Mac", "Open Focus, choose Session › iPhone…, then Pair a phone. A code appears.")
                    macPicker
                    step(2, "Type the code", "It's 16 letters and numbers.")
                    TextField("XXXX-XXXX-XXXX-XXXX", text: $code)
                        .font(.system(.title3, design: .monospaced).weight(.medium))
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().keyboardType(.asciiCapable)
                        .focused($codeFocused).submitLabel(.go).onSubmit(pair)
                        .padding(16).background(Palette.surface, in: .rect(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(problem == nil ? Palette.line : Palette.drift.opacity(0.7)) }
                        .onChange(of: code) { _, new in let f = Self.format(new); if f != new { code = f }; problem = nil }
                    if let problem { Text(problem).font(.subheadline).foregroundStyle(Palette.drift).transition(.opacity) }
                    PrimaryButton(title: working ? "Pairing…" : "Pair", systemImage: working ? nil : "link", action: pair).disabled(!ready)
                }
                .padding(Metrics.gutter)
                .motion(Motion.settle, value: problem)
            }
            .background(Palette.canvas)
            .navigationTitle("Add your Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
        .onAppear { model.client.browse() }
        .successFeedback(paired)
        .interactiveDismissDisabled(working)
    }

    @ViewBuilder private var macPicker: some View {
        if found.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("Looking for your Mac on this Wi-Fi…").font(.subheadline).foregroundStyle(Palette.ink2)
            }
            .frame(minHeight: 44)
        } else {
            VStack(spacing: 8) {
                ForEach(found) { mac in
                    let on = (selected ?? found.first)?.id == mac.id
                    Button { selected = mac; codeFocused = true } label: {
                        HStack {
                            Image(systemName: "macbook").symbolRenderingMode(.hierarchical)
                            Text(mac.name).font(.body.weight(.medium))
                            Spacer()
                            if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent).transition(.scale.combined(with: .opacity)) }
                        }
                        .padding(14).frame(minHeight: 52)
                        .background(on ? Palette.accentSoft : Palette.surface, in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(PressScale())
                }
            }
            .motion(Motion.land, value: selected?.id)
        }
    }

    private func step(_ n: Int, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").font(.footnote.weight(.bold)).foregroundStyle(Palette.onAccent).frame(width: 26, height: 26).background(Palette.accent, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(Palette.ink2)
            }
        }
    }

    private func pair() {
        guard ready, let mac = selected ?? found.first else { return }
        working = true; problem = nil; codeFocused = false
        model.pair(with: mac, code: code, deviceName: UIDevice.current.name) { error in
            working = false
            if let error { problem = error } else { paired += 1; dismiss() }
        }
    }

    /// Uppercase, only letters the code can use, and a dash after every four.
    static func format(_ text: String) -> String {
        let allowed = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZOIL")
        let chars = text.uppercased().filter { allowed.contains($0) }.prefix(16)
        return stride(from: 0, to: chars.count, by: 4).map { i in
            let s = chars.index(chars.startIndex, offsetBy: i), e = chars.index(s, offsetBy: min(4, chars.count - i))
            return String(chars[s..<e])
        }.joined(separator: "-")
    }
}
