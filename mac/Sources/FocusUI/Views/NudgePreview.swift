import SwiftUI

/// A nudge as the notch shows it on a screen without a notch, for the Nudges page: the ring, the words in the tone you picked, one line
/// of what Focus saw, and the one way forward. It only shows; nothing here is a button.
struct NudgePreviewPill: View {
    var text: String
    /// The pill's own geometry, so the preview never drifts from the real thing.
    static let size = NotchLayout.size(.nudge, notchWidth: 0, notchHeight: 0)
    static let radius = NotchLayout.radii(.nudge, shown: true, pill: true).bottom
    var body: some View {
        HStack(spacing: 14) {
            RingView(.drift, color: Tokens.Notch.slip).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(text).font(Tokens.fixed(.headline, .semibold)).foregroundStyle(NotchView.ink).lineLimit(1)
                    .contentTransition(.interpolate)
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").foregroundStyle(NotchView.accent)
                    Text(CueCopy.reminderMeta)
                    Text("2:14").monospacedDigit().foregroundStyle(Tokens.Notch.slip)
                }
                .font(Tokens.fixed(.caption, .medium)).foregroundStyle(NotchView.ink2)
            }
            Spacer(minLength: Space.m)
            Text("Back to task").font(Tokens.fixed(.body, .semibold)).foregroundStyle(Tokens.Notch.onAccent)
                .padding(.horizontal, 18).frame(height: 32).background(Capsule().fill(NotchView.accent))
        }
        .padding(.leading, 18).padding(.trailing, 14)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).fill(.black))
        .overlay { RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(Color.white.opacity(0.08)) }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .motion(Motion.notchSettle, value: text)
        .accessibilityElement(children: .combine)
    }
}
