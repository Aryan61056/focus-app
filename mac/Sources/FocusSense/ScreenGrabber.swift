import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Takes one picture of the window the user is looking at. Pictures are returned to the caller and nowhere else:
/// nothing here writes a file, and nothing here sends a picture to the model (the judge reads text).
public protocol ScreenGrabber {
    /// True once the user has allowed Screen Recording for this app.
    var isAllowed: Bool { get }
    /// Shows the system prompt the first time; afterwards it does nothing.
    func requestAccess()
    /// The front window of the app in front, or nil (Focus itself in front, nothing visible, or no permission).
    func grab() async -> (image: CGImage, app: String)?
}

/// ScreenCaptureKit: the front app's largest normal window, scaled to 1600 px wide so text stays readable, no cursor.
/// Unverified on a real display: it needs Screen Recording granted by the user, which an agent cannot do.
public struct SCKScreenGrabber: ScreenGrabber {
    public static let captureWidth = 1600
    public init() {}

    public var isAllowed: Bool { CGPreflightScreenCaptureAccess() }
    public func requestAccess() { _ = CGRequestScreenCaptureAccess() }

    public func grab() async -> (image: CGImage, app: String)? {
        guard isAllowed, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() else { return nil }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return nil }
        let candidates = content.windows.filter { $0.owningApplication?.processID == front.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 120 && $0.frame.height > 80 }
        guard let win = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return nil }
        let cfg = SCStreamConfiguration()
        let w = min(Self.captureWidth, Int(win.frame.width))
        cfg.width = w; cfg.height = max(1, Int(CGFloat(w) * win.frame.height / win.frame.width))
        cfg.showsCursor = false
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg) else { return nil }
        return (img, front.localizedName ?? "")
    }
}
