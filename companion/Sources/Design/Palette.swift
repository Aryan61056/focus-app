import SwiftUI

extension UIColor {
    // nonisolated: SwiftUI resolves dynamic colors on a render thread, and the project defaults to the main actor.
    nonisolated convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// The Mac app's "Workspace" look on a phone: neutral grays, one green accent, amber only for a slip, and shape (not color) carrying state.
enum Palette {
    static let accent = Color(light: 0x1B7548, dark: 0x78D59D)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x041B0E)
    static let accentSoft = Color(light: 0xD9F3E2, dark: 0x1E3D2A)
    static let ink = Color(light: 0x1A1B1B, dark: 0xEDEEEE)
    static let ink2 = Color(light: 0x56595A, dark: 0xA9ADAE)
    static let canvas = Color(light: 0xF7F7F6, dark: 0x1B1B1B)
    static let surface = Color(light: 0xFFFFFF, dark: 0x242424)
    /// Wells (fields, the Hushd bar) sunk into the canvas.
    static let well = Color(light: 0xF0F0EF, dark: 0x202020)
    static let line = Color(light: 0x1A1B1B, dark: 0xFFFFFF).opacity(0.1)
    static let track = Color(light: 0x1A1B1B, dark: 0xFFFFFF).opacity(0.16)
    /// A slip is amber, the Mac's `Tokens.slip`: never an alarm red, never the only sign.
    static let drift = Color(light: 0xB86A00, dark: 0xF0B060)
}

enum Metrics {
    static let gutter: CGFloat = 20
    static let card: CGFloat = 24
    static let control: CGFloat = 52
}
