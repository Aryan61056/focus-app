import SwiftUI

struct Panel<Content: View>: View {
    var tinted = false
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 20).padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusCard).fill(tinted ? Tokens.window2 : Tokens.window))
            .overlay { if !tinted { RoundedRectangle(cornerRadius: Tokens.radiusCard).strokeBorder(Tokens.line) } }
    }
}

struct StateChip: View {
    var label: String, ring: RingState, on = true
    var body: some View {
        HStack(spacing: 6) {
            RingView(ring, color: on ? Tokens.accent : Tokens.ink).frame(width: 14, height: 14)
            Text(label).font(Tokens.text(12.5, .semibold))
        }
        .padding(.leading, 6).padding(.trailing, 10).frame(height: 24)
        .background(Capsule().fill(on ? Tokens.accentSoft : Tokens.control))
        .accessibilityElement(children: .ignore).accessibilityLabel(label)
    }
}

struct SectionTitle: View {
    var text: String
    var body: some View { Text(text).font(Tokens.text(15, .semibold)).accessibilityAddTraits(.isHeader) }
}
