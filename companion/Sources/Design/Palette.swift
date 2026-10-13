import SwiftUI

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// The Mac app's "Lichen" direction on a phone: one calm green, ink instead of black, and shape (not color) carrying state.
enum Palette {
    static let accent = Color(light: 0x1B7548, dark: 0x78D59D)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x041B0E)
    static let accentSoft = Color(light: 0xD9F3E2, dark: 0x1E3D2A)
    static let ink = Color(light: 0x161C18, dark: 0xEEF3EF)
    static let ink2 = Color(light: 0x4D554F, dark: 0xB1BAB4)
    static let canvas = Color(light: 0xF3F7F4, dark: 0x0D110E)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1A201B)
    static let line = Color(light: 0x161C18, dark: 0xFFFFFF).opacity(0.1)
    static let track = Color(light: 0x161C18, dark: 0xFFFFFF).opacity(0.14)
    /// Drift is quiet on purpose: a warmer ink, never an alarm red.
    static let drift = Color(light: 0x7A4A12, dark: 0xE9B878)
}

enum Metrics {
    static let gutter: CGFloat = 20
    static let card: CGFloat = 24
    static let control: CGFloat = 52
}
