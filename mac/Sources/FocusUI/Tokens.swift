import SwiftUI
import AppKit

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

    public static let radiusCard: CGFloat = 16
    public static let radiusControl: CGFloat = 9
    /// The widest a screen's content gets, so lines and tables stay readable on a large display.
    public static let contentWidth: CGFloat = 1120
    public static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded) }
    public static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
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
                .font(Tokens.text(small ? 12.5 : 13, .semibold))
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
