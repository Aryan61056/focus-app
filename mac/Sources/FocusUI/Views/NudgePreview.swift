import SwiftUI

/// A nudge as the notch shows it, for the Nudges page: the words and the one way forward. It only shows; nothing here is a button.
struct NudgePreviewPill: View {
    var text: String
    var body: some View {
        HStack(spacing: Space.m) {
            Text(text).font(Tokens.fixed(.headline, .semibold, rounded: true)).foregroundStyle(NotchView.ink).lineLimit(1)
                .contentTransition(.interpolate)
            Text("Back to task").font(Tokens.fixed(.caption, .semibold)).foregroundStyle(Tokens.Notch.onAccent)
                .padding(.horizontal, Space.m).frame(height: 28).background(Capsule().fill(NotchView.accent))
        }
        .padding(.leading, Space.xl).padding(.trailing, Space.s)
        .frame(height: 52)
        .background(Capsule().fill(.black))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .motion(Motion.notchSettle, value: text)
        .accessibilityElement(children: .combine)
    }
}
