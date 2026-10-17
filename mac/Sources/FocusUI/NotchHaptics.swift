import AppKit

/// The notch's feel under a finger on a Force Touch trackpad. The Mac gives apps three shapes of tap, so each moment gets the one
/// that suits it: a soft detent for pressing and changing page, a firmer step for opening and for a file landing. Hovering never taps
/// (it happens dozens of times a day), and a nudge keeps its own cue.
@MainActor public enum NotchHaptics {
    public enum Kind: Equatable, Sendable {
        /// Mouse down on the closed notch, as it squeezes in.
        case pressed
        /// The click landed and the card opened.
        case opened
        /// Home, Tray or Widgets.
        case page
        /// A dragged file reached the notch and the tray took over.
        case entered
        /// The file dropped into the tray.
        case landed

        var pattern: NSHapticFeedbackManager.FeedbackPattern {
            switch self {
            case .pressed, .page, .entered: return .alignment
            case .opened, .landed: return .levelChange
            }
        }
    }

    /// Taps closer together than this are one gesture; the second is dropped, so a press then an open do not stutter.
    private static var last: (kind: Kind, at: Date)?
    static let gap: TimeInterval = 0.06

    public static func play(_ kind: Kind, now: Date = .now) {
        if let last, now.timeIntervalSince(last.at) < gap { return }
        last = (kind, now)
        NSHapticFeedbackManager.defaultPerformer.perform(kind.pattern, performanceTime: .now)
    }
}
