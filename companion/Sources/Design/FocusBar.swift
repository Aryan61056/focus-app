import SwiftUI
import FocusLinkNet

/// "Focus is reading", the Mac's reading bar on a phone: the sparkle that marks where the AI is working, and what it is doing. The phone
/// never sees window names, so it says only that the Mac is watching.
struct FocusBar: View {
    var phase: SessionState.Phase
    private var text: LocalizedStringKey {
        switch phase {
        case .idle: "Waiting for a session"
        case .paused: "Paused. Not reading"
        case .onBreak: "On a break. Not reading"
        default: "Reading on your Mac"
        }
    }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
            Text("Hushd").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
            Text(text).font(.footnote).foregroundStyle(Palette.ink2).contentTransition(.interpolate)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(minHeight: 40)
        .background(Palette.well, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line) }
        .motion(Motion.settle, value: phase)
        .accessibilityElement(children: .combine)
    }
}
