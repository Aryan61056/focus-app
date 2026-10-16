import SwiftUI
import AppKit

/// A card. Same surface as Tile with the smaller inner padding; `tinted` sinks it into the canvas instead of raising it.
struct Panel<Content: View>: View {
    var tinted = false
    @ViewBuilder var content: Content
    var body: some View {
        // A grouped section, as Droppy's and System Settings' forms draw them: a quiet rounded card a step lighter than the window.
        if tinted {
            content.padding(.horizontal, 14).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Tokens.accent.opacity(0.1)))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Tokens.cardEdge) }
        } else {
            Tile(padding: 14) { content }
        }
    }
}

/// The one raised surface: a card a step above the canvas, with a hairline edge and, in light mode, a soft shadow so it lifts off the page.
struct Tile<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSurface(radius: 10))
    }
}

struct CardSurface: ViewModifier {
    var radius: CGFloat = 10
    var fill: Color = Tokens.card
    /// The micro dot texture: a faint grid fading from the top-right corner, and a pool of accent dots under the pointer.
    var dots = true
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // Flat, as Droppy's grouped cards are: the fill and a hairline carry it, with only a whisper of shadow in light mode.
        content
            .background(shape.fill(fill).shadow(color: .black.opacity(scheme == .dark ? 0 : 0.03), radius: 1, y: 1))
            .modifier(DotsIf(on: dots, radius: radius))
            .overlay { shape.strokeBorder(Tokens.cardEdge) }
    }
}

private struct DotsIf: ViewModifier {
    var on: Bool
    var radius: CGFloat
    func body(content: Content) -> some View {
        if on { content.dotTexture(radius: radius) } else { content }
    }
}

/// Every screen's title block: one quiet line and at most one action on the right. The title itself sits in the toolbar, as in
/// Droppy, so it is not repeated in the page; it stays here for VoiceOver.
struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                if let subtitle { Text(subtitle).font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 16)
            trailing
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}
extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

/// A choice among a few options (Open or Timed, a tone, a check rate). Selected is a filled pill with accent text, the rest are quiet.
/// One shared style so the same control never looks different on two screens.
struct ChoiceStyle: ButtonStyle {
    var on: Bool
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration, on: on) }
    struct Inner: View {
        let configuration: Configuration
        let on: Bool
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(Tokens.text(12.5, .semibold))
                .foregroundStyle(on ? Tokens.accentInk : Tokens.ink)
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(on ? Tokens.accentSoft : (hover ? Tokens.controlHover : Tokens.control)))
                .opacity(configuration.isPressed ? 0.8 : 1)
                .contentShape(Capsule())
                .onHover { hover = $0 }
                .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}

/// A row of choices in the shared style.
struct ChoiceRow<T: Hashable>: View {
    var items: [T]
    @Binding var selection: T
    var title: (T) -> String
    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button(title(item)) { selection = item }.buttonStyle(ChoiceStyle(on: selection == item))
            }
        }
    }
}

/// A field sunk into its card. Used for every free-text input so they share one look.
struct WellField: ViewModifier {
    var height: CGFloat? = 36
    var focused = false
    /// Inside a well (a tinted panel) a field is raised to the card color instead, so it still reads as a field.
    var raised = false
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).padding(.horizontal, 12).frame(height: height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(raised ? Tokens.window2 : Tokens.well))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(focused ? Tokens.accent : Tokens.line, lineWidth: focused ? 1.5 : 0.5) }
    }
}
extension View {
    func wellField(height: CGFloat? = 36, focused: Bool = false, raised: Bool = false) -> some View { modifier(WellField(height: height, focused: focused, raised: raised)) }
}

/// What a screen shows before it has anything: what will appear here and how to get it, with one way forward.
struct EmptyState<Action: View>: View {
    var symbol = "circle.dashed"
    var title: String, text: String
    @ViewBuilder var action: Action
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(Tokens.accent)
                .frame(width: 52, height: 52).background(Circle().fill(Tokens.accentSoft))
            VStack(spacing: 6) {
                Text(title).font(Tokens.rounded(18, .semibold))
                Text(text).font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
            action
        }
        .padding(.vertical, 44).padding(.horizontal, 24).frame(maxWidth: .infinity)
        // Printed rings spread out from the symbol as the empty page arrives, then rest and swell under the pointer.
        .background {
            GeometryReader { g in
                Halftone(pattern: .rings(center: UnitPoint(x: 0.5, y: 70 / max(1, g.size.height)), aspect: g.size.width / max(1, g.size.height)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .modifier(CardSurface(radius: 10, dots: false))
        .accessibilityElement(children: .contain)
    }
}
extension EmptyState where Action == EmptyView {
    init(symbol: String = "circle.dashed", title: String, text: String) { self.init(symbol: symbol, title: title, text: text) { EmptyView() } }
}

/// The app's own icon when it is installed, so a window is recognised at a glance. Falls back to a plain window glyph.
/// It looks up the name already shown beside it; nothing new is read.
struct AppIcon: View {
    var name: String
    var size: CGFloat = 38
    var body: some View {
        Group {
            if let img = Self.icon(for: name) { Image(nsImage: img).resizable().interpolation(.high) }
            else {
                Image(systemName: name == "Private window" ? "lock" : "macwindow").font(.system(size: size * 0.42)).foregroundStyle(Tokens.ink2)
                    .frame(width: size, height: size).background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(Tokens.control))
            }
        }
        .frame(width: size, height: size).accessibilityHidden(true)
    }
    @MainActor static var cache: [String: NSImage] = [:]
    @MainActor static func icon(for name: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        if let hit = cache[name] { return hit }
        let running = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.icon
        let found = running ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.\(name.replacingOccurrences(of: " ", with: ""))")
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        if let found { cache[name] = found }
        return found
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
