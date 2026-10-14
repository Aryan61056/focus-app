import SwiftUI

/// The one primary action on a screen.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).font(.body.weight(.semibold)) }
                Text(title).font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: Metrics.control)
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.accent)
        .controlSize(.large)
    }
}

/// A quiet secondary action in glass.
struct SoftButton: View {
    let title: LocalizedStringKey
    var systemImage: String
    var role: ButtonRole?
    var action: () -> Void
    var body: some View {
        Button(role: role, action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title3.weight(.medium)).symbolRenderingMode(.hierarchical)
                Text(title).font(.footnote.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(role == .destructive ? Palette.drift : Palette.ink)
        }
        .buttonStyle(PressScale())
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: .rect(cornerRadius: Metrics.card))
            .overlay { RoundedRectangle(cornerRadius: Metrics.card).strokeBorder(Palette.line) }
    }
}

struct Eyebrow: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View { Text(text).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink2).textCase(.uppercase).tracking(0.6) }
}

extension TimeInterval {
    /// 1:05:09 or 12:04.
    var clockText: String {
        let n = max(0, Int(self.rounded(.down))), h = n / 3600, m = (n % 3600) / 60, s = n % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
    /// "1 h 20 min", "45 min", "under a minute".
    var spokenText: String {
        let m = Int((self / 60).rounded())
        if m < 1 { return String(localized: "under a minute") }
        let h = m / 60
        return h > 0 ? (m % 60 == 0 ? String(localized: "\(h) h") : String(localized: "\(h) h \(m % 60) min")) : String(localized: "\(m) min")
    }
}
