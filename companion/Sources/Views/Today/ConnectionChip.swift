import SwiftUI

/// Where the phone stands with the Mac, always visible so a silent failure to connect is never a surprise.
struct ConnectionChip: View {
    @Environment(AppModel.self) private var model

    private var info: (text: LocalizedStringKey, symbol: String, live: Bool) {
        switch model.connection {
        case .connected: ("Connected", "checkmark.circle.fill", true)
        case .demo: ("Demo", "sparkles", true)
        case .connecting: ("Connecting", "arrow.triangle.2.circlepath", false)
        case .searching: ("Looking for your Mac", "magnifyingglass", false)
        case .offline: ("Offline", "wifi.slash", false)
        case .unpaired: ("Not paired", "macbook.and.iphone", false)
        }
    }

    var body: some View {
        let i = info
        // An explicit HStack, not a Label (a toolbar collapses a Label to its icon). The toolbar draws the glass behind it.
        HStack(spacing: 6) {
            Image(systemName: i.symbol).contentTransition(.symbolEffect(.replace))
            Text(i.text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(i.live ? Palette.accent : Palette.ink2)
        .fixedSize()
        .motion(Motion.settle, value: model.connection)
        .accessibilityElement(children: .combine)
    }
}
