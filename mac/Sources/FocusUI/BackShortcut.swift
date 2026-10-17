import Carbon.HIToolbox
import SwiftUI

/// The key that does "Back to task" from any app. It needs no extra permission. Off is a choice because every global key can clash with another app's.
public enum BackShortcut: String, CaseIterable, Identifiable, Sendable {
    case controlOptionB, controlOptionR, commandControlB, off
    public var id: Self { self }
    public var label: String {
        switch self { case .controlOptionB: return "\u{2303}\u{2325}B"; case .controlOptionR: return "\u{2303}\u{2325}R"; case .commandControlB: return "\u{2303}\u{2318}B"; case .off: return "Off" }
    }
    public var isOn: Bool { self != .off }
    public var keyCode: UInt32 { UInt32(self == .controlOptionR ? kVK_ANSI_R : kVK_ANSI_B) }
    public var carbonModifiers: UInt32 { UInt32(controlKey | (self == .commandControlB ? cmdKey : optionKey)) }
}
