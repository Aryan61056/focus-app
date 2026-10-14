import SwiftUI

struct Panel<Content: View>: View {
    var tinted = false
    @ViewBuilder var content: Content
    var body: some View {
        // A grouped section, as Droppy's and System Settings' forms draw them: a quiet rounded card a step lighter than the window.
        content
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tinted ? Tokens.accent.opacity(0.1) : Tokens.card))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Tokens.cardEdge) }
    }
}

struct StateChip: View {
    var label: String, ring: RingState, on = true
    var body: some View {
        HStack(spacing: 6) {
            LiveRing(ring, color: on ? Tokens.accent : Tokens.ink).frame(width: 14, height: 14)
            Text(label).font(Tokens.text(12.5, .semibold)).contentTransition(.interpolate)
        }
        .padding(.leading, 6).padding(.trailing, 10).frame(height: 24)
        .background(Capsule().fill(on ? Tokens.accentSoft : Tokens.control))
        .motion(Motion.notchSettle, value: label)
        .motion(Motion.out(0.3), value: on)
        .accessibilityElement(children: .ignore).accessibilityLabel(label)
    }
}

struct SectionTitle: View {
    var text: String
    var body: some View { Text(text).font(Tokens.text(13, .semibold)).padding(.leading, 9).accessibilityAddTraits(.isHeader) }
}

/// Offscreen snapshots (ImageRenderer) cannot draw ScrollView content, so the snapshot tool turns scrolling off.
public enum SnapshotMode { @MainActor public static var on = false }

struct Scroller<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if SnapshotMode.on { content } else { ScrollView { content }.scrollIndicators(.hidden) }
    }
}

/// Marks any text the on-device model wrote, so it is never mistaken for a fact or a setting the user made.
struct AITag: View {
    var body: some View {
        Label("On-device AI", systemImage: "sparkles").labelStyle(.titleAndIcon)
            .font(Tokens.text(11.5, .medium)).foregroundStyle(Tokens.ink2)
            .padding(.horizontal, 8).frame(height: 20)
            .overlay { Capsule().strokeBorder(Tokens.line) }
            .accessibilityLabel("Written by the on-device model. It can be wrong.")
    }
}

/// A small pulsing ring while the model is working. Stands still with Reduce Motion.
struct ThinkingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        Circle().strokeBorder(Tokens.accent, lineWidth: 2).frame(width: 12, height: 12)
            .scaleEffect(on && !reduceMotion ? 1.25 : 1).opacity(on && !reduceMotion ? 0.5 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
            .accessibilityHidden(true)
    }
}
