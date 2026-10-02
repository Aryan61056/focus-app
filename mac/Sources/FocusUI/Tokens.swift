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
    public static let ink = Color(light: 0x161C18, dark: 0xEEF3EF)
    public static let ink2 = Color(light: 0x4D554F, dark: 0xB1BAB4)
    public static let window = Color(light: 0xFBFDFC, dark: 0x1C211D)
    public static let window2 = Color(light: 0xF3F7F4, dark: 0x232925)
    public static let sidebar = Color(light: 0xECF2EE, dark: 0x141915)
    public static let line = Color(light: 0x161C18, dark: 0xFFFFFF, lightAlpha: 0.12, darkAlpha: 0.11)
    public static let control = Color(light: 0x161C18, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.1)
    public static let controlHover = Color(light: 0x161C18, dark: 0xFFFFFF, lightAlpha: 0.12, darkAlpha: 0.17)
    public static let track = Color(light: 0x161C18, dark: 0xFFFFFF, lightAlpha: 0.18, darkAlpha: 0.22)

    public static let radiusCard: CGFloat = 16
    public static let radiusControl: CGFloat = 9
    public static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded) }
    public static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
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
                .background(RoundedRectangle(cornerRadius: Tokens.radiusControl).fill(fill))
                .overlay { if kind == .plain { RoundedRectangle(cornerRadius: Tokens.radiusControl).strokeBorder(Tokens.line) } }
                .opacity(enabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
                .onHover { hover = $0 }
                .contentShape(RoundedRectangle(cornerRadius: Tokens.radiusControl))
        }
        var fill: Color {
            switch kind {
            case .primary: return hover ? Tokens.accent.opacity(0.88) : Tokens.accent
            case .secondary: return hover ? Tokens.controlHover : Tokens.control
            case .plain: return hover ? Tokens.control : .clear
            }
        }
    }
}
