import SwiftUI
import AppKit
import Observation

/// Direction B (Lichen) as native tokens. Values are the OKLCH tokens in docs/design/b-lichen.css converted to sRGB.
extension Color {
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

public enum Tokens {
    public static let accent = Color(light: 0x1B7548, dark: 0x78D59D)
    public static let onAccent = Color(light: 0xFFFFFF, dark: 0x041B0E)
    public static let accentSoft = Color(light: 0xD9F3E2, dark: 0x1E3D2A)
    /// Accent as text on accentSoft (a selected choice): darker in light, lighter in dark, so it clears 4.5:1.
    public static let accentInk = Color(light: 0x125233, dark: 0xA3EBBE)
    public static let ink = Color(light: 0x161C18, dark: 0xEEF3EF)
    public static let ink2 = Color(light: 0x4D554F, dark: 0xB1BAB4)
    /// Three layers, so a screen reads at a glance: the canvas, raised cards on it, and wells (fields, insets) sunk into a card.
    /// Light: cards are white on a faintly green canvas. Dark: cards are lighter than the canvas. The sidebar is the second neutral layer.
    public static let window = Color(light: 0xF4F7F5, dark: 0x181D19)
    public static let window2 = Color(light: 0xFFFFFF, dark: 0x222824)
    public static let well = Color(light: 0xEFF3F0, dark: 0x1A1F1B)
    public static let sidebar = Color(light: 0xE9EFEB, dark: 0x121613)
    public static let line = Color(light: 0x161C18, dark: 0xFFFFFF, lightAlpha: 0.12, darkAlpha: 0.11)
    public static let control = Color(light: 0x161C18, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.1)
    public static let controlHover = Color(light: 0x161C18, dark: 0xFFFFFF, lightAlpha: 0.12, darkAlpha: 0.17)
    /// A grouped card on the plain window gray: white in light mode, a faint lift in dark, as native grouped forms draw them.
    public static let card = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.85, darkAlpha: 0.045)
    public static let cardEdge = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.05)
    public static let track = Color(light: 0x161C18, dark: 0xFFFFFF, lightAlpha: 0.18, darkAlpha: 0.22)

    /// The notch is always black, whatever the system appearance, so it has its own fixed colors (on black: ink 18.6:1,
    /// ink2 10.6:1, accent 11.9:1, onAccent on accent 10.3:1; tools/check_contrast.py).
    public enum Notch {
        public static let ink = Color(red: 0.93, green: 0.95, blue: 0.94)
        public static let ink2 = Color(red: 0.70, green: 0.73, blue: 0.71)
        public static let accent = Color(red: 0.47, green: 0.84, blue: 0.62)
        public static let onAccent = Color(red: 0.02, green: 0.1, blue: 0.05)
        public static let track = Color.white.opacity(0.16)
    }
    /// Colors of drawn artwork (the page banner, the session disc in the sidebar, the notch widgets). Never used for text.
    public enum Art {
        public static let sky = [Color(red: 0.03, green: 0.22, blue: 0.16), Color(red: 0.05, green: 0.40, blue: 0.27), Color(red: 0.10, green: 0.55, blue: 0.36)]
        public static let skyDark = [Color(red: 0.02, green: 0.12, blue: 0.09), Color(red: 0.04, green: 0.22, blue: 0.15), Color(red: 0.07, green: 0.31, blue: 0.21)]
        public static let disc = [Color(red: 0.42, green: 0.80, blue: 0.56), Color(red: 0.16, green: 0.50, blue: 0.32)]
        /// The green of the Today and Nudges tiles in the sidebar, beside the system's own blue, orange and purple.
        public static let leaf = Color(red: 0.16, green: 0.62, blue: 0.38)
    }

    // MARK: shape
    /// Corner radii, one step per kind of thing, so a card never sits next to a card of another radius.
    /// Bars and heat cells, rows that light up, fields and insets inside a card, cards, and floating cards (nudge, check-in, shield).
    public static let radiusTiny: CGFloat = 4
    public static let radiusRow: CGFloat = 8
    public static let radiusInset: CGFloat = 10
    public static let radiusCard: CGFloat = 12
    public static let radiusFloat: CGFloat = 22
    /// Buttons drawn without glass (macOS 14 and 15) and small filled controls.
    public static let radiusControl: CGFloat = 8
    /// The smallest a click target gets (WCAG 2.2, 2.5.8). Icons can be smaller; their hit area is not.
    public static let minHit: CGFloat = 24
    /// The widest a screen's content gets, so lines and tables stay readable on a large display.
    public static let contentWidth: CGFloat = 1120

    // MARK: type
    /// The one type scale. Hierarchy comes from these steps and from weight and color, never from a one-off size.
    /// Caption2 for axis labels and badges, caption for secondary lines, body for most text, callout for a card's title, headline for
    /// a floating card's question, title3 for a section's lead line, title2 for a screen's main line, display for the clock and goal.
    public enum Step: CGFloat, CaseIterable, Sendable {
        case caption2 = 11, caption = 12, body = 13, callout = 14, headline = 16, title3 = 20, title2 = 26, display = 34
    }
    /// SF Pro at a step, scaled by the Text size setting. Reading `TextScale.shared` inside a view body makes that view redraw when the
    /// setting changes, so no call site needs to know about it.
    public static func text(_ step: Step, _ weight: Font.Weight = .regular) -> Font { .system(size: step.rawValue * TextScale.shared.factor, weight: weight) }
    /// SF Pro Rounded at a step, for numerals and the few display lines (Lichen uses the rounded face for numbers).
    public static func rounded(_ step: Step, _ weight: Font.Weight = .semibold) -> Font { .system(size: step.rawValue * TextScale.shared.factor, weight: weight, design: .rounded) }
    /// A symbol sized in points, scaled with the text it sits beside.
    public static func symbol(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size * TextScale.shared.factor, weight: weight) }
    /// The notch and the over-window banner have fixed heights set by the hardware notch and the menu bar, so their text does not scale.
    public static func fixed(_ step: Step, _ weight: Font.Weight = .regular, rounded: Bool = false) -> Font {
        .system(size: step.rawValue, weight: weight, design: rounded ? .rounded : .default)
    }
}

/// Space, on a 4 point grid. Inside a row 4 to 8, between parts of a card 12 to 16, card padding 20, between cards 24, page sections 32.
public enum Space {
    public static let xxs: CGFloat = 4, xs: CGFloat = 8, s: CGFloat = 12, m: CGFloat = 16, l: CGFloat = 20, xl: CGFloat = 24, xxl: CGFloat = 32
}

/// How much larger the app window's text is drawn (General, Text size). Observable, so views that read it through `Tokens` redraw.
@Observable public final class TextScale: @unchecked Sendable {
    nonisolated(unsafe) public static let shared = TextScale()
    public var factor: CGFloat = 1
    /// Choices offered in Settings. 150 percent is the largest the window's layouts are checked at.
    public static let choices: [(title: String, factor: CGFloat)] = [("Default", 1), ("Large", 1.15), ("Larger", 1.3), ("Largest", 1.5)]
}

/// Motion, named for what it is for. Entering and leaving use a strong ease-out; anything that grows, follows the pointer or can be
/// interrupted is a spring. Every caller checks Reduce Motion and falls back to `Motion.reduced`: the change stays, the travel goes.
public enum Motion {
    /// Entering or leaving: starts fast, so the eye gets the change at once.
    public static func out(_ duration: Double = 0.22) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
    /// Hover and color: short enough to feel attached to the pointer.
    public static let hover = Animation.easeOut(duration: 0.12)
    /// Selection sliding between rows; a spring so a quick second click retargets from where it is.
    public static let glide = Animation.spring(duration: 0.32, bounce: 0)
    // The notch's springs, from Droppy's notch as recorded frame by frame on this Mac (2026-10-13): hover reaches its width in about
    // 0.1 s with almost no overshoot; a click opens in about 0.35 s with 1 to 2 percent overshoot; leaving closes in about 0.35 s.
    /// Hover: the ears widen quickly.
    public static let notchPeek = Animation.spring(response: 0.24, dampingFraction: 0.78)
    /// A click or a nudge opens the full card.
    public static let notchOpen = Animation.spring(response: 0.38, dampingFraction: 0.8)
    /// Back to the resting band.
    public static let notchClose = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// Mouse down on the notch: it squeezes in before it opens.
    public static let notchPress = Animation.spring(response: 0.16, dampingFraction: 0.86)
    /// Things elsewhere in the app that settle into place (a chip, a ring changing shape): quick, a little give.
    public static let notchSettle = Animation.spring(response: 0.3, dampingFraction: 0.8)
    /// The notch tucking back into the hardware notch when a session ends: no bounce, it is leaving.
    public static let notchTuck = Animation.spring(response: 0.3, dampingFraction: 1)
    /// A progress arc running down: constant motion is linear.
    public static let tick = Animation.linear(duration: 1)
    /// Reduce Motion: a short fade in place of any travel.
    public static let reduced = Animation.easeOut(duration: 0.15)
}

extension View {
    /// `animation(_:value:)` that swaps to a short fade under Reduce Motion.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View { modifier(MotionModifier(animation: animation, value: value)) }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View { content.animation(reduceMotion ? Motion.reduced : animation, value: value) }
}

extension AnyTransition {
    /// A card that drops in from the corner it is pinned to. Opacity only with Reduce Motion (the caller passes `reduce`).
    static func card(from anchor: UnitPoint, reduce: Bool) -> AnyTransition {
        reduce ? AnyTransition.opacity : .asymmetric(
            insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.9, anchor: anchor)).combined(with: AnyTransition(.blurReplace)).animation(Motion.notchOpen),
            removal: AnyTransition.opacity.combined(with: .scale(scale: 0.96, anchor: anchor)).animation(Motion.out(0.18)))
    }
    /// A panel or line arriving in a list: rises a few points and fades in, and leaves faster than it came.
    static func rise(reduce: Bool) -> AnyTransition {
        let move = reduce ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .offset(y: 6))
        return .asymmetric(insertion: move.animation(Motion.out(0.26)),
                    removal: AnyTransition.opacity.animation(Motion.out(0.14)))
    }
}

extension View {
    /// Liquid Glass on macOS 26 and later; the closest material before it. Reduce Transparency gets a solid fill.
    @ViewBuilder func glassSurface(_ shape: some Shape, tint: Color? = nil, interactive: Bool = false, fallback: Color = Tokens.window2) -> some View {
        modifier(GlassSurface(shape: AnyShape(shape), tint: tint, interactive: interactive, fallback: fallback))
    }
}

private struct GlassSurface: ViewModifier {
    let shape: AnyShape
    let tint: Color?
    let interactive: Bool
    let fallback: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(shape.fill(tint ?? fallback))
        } else if #available(macOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(shape.fill(tint ?? Color.clear)).background(.regularMaterial, in: shape)
        }
    }
    @available(macOS 26, *) var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        return interactive ? g.interactive() : g
    }
}

public enum FocusButtonKind { case primary, secondary, plain }

public struct FocusButtonStyle: ButtonStyle {
    public var kind: FocusButtonKind
    public var small = false
    public var expand = false
    public init(_ kind: FocusButtonKind = .secondary, small: Bool = false, expand: Bool = false) { self.kind = kind; self.small = small; self.expand = expand }

    public func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, kind: kind, small: small, expand: expand)
    }

    struct Inner: View {
        let configuration: Configuration
        let kind: FocusButtonKind
        let small: Bool
        let expand: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .font(Tokens.text(small ? .caption : .body, .semibold))
                .foregroundStyle(kind == .primary ? Tokens.onAccent : Tokens.ink)
                .frame(maxWidth: expand ? .infinity : nil)
                .padding(.horizontal, small ? 11 : 13)
                .frame(height: small ? 28 : (kind == .primary ? 34 : 32))
                .background { if !glass { RoundedRectangle(cornerRadius: Tokens.radiusControl).fill(fill) } }
                .overlay { if kind == .plain { Capsule().strokeBorder(Tokens.line) } }
                .modifier(GlassButtonBody(kind: kind, on: glass))
                .opacity(enabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(reduceMotion ? nil : Motion.out(0.14), value: configuration.isPressed)
                .animation(Motion.hover, value: hover)
                .onHover { hover = $0 }
                .contentShape(RoundedRectangle(cornerRadius: Tokens.radiusControl))
        }
        /// Primary and secondary buttons are Liquid Glass capsules on macOS 26: the system draws hover, press and the light that follows the pointer.
        var glass: Bool { if #available(macOS 26, *) { return kind != .plain } else { return false } }
        var fill: Color {
            switch kind {
            case .primary: return hover ? Tokens.accent.opacity(0.88) : Tokens.accent
            case .secondary: return hover ? Tokens.controlHover : Tokens.control
            case .plain: return hover ? Tokens.control : .clear
            }
        }
    }
}

private struct GlassButtonBody: ViewModifier {
    let kind: FocusButtonKind
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content.glassSurface(Capsule(), tint: kind == .primary ? Tokens.accent : nil, interactive: true, fallback: kind == .primary ? Tokens.accent : Tokens.control)
        } else {
            content
        }
    }
}
