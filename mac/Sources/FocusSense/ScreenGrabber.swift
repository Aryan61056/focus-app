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
    /// The front window of the app in front, or nil (Hushd itself in front, nothing visible, or no permission).
    func grab() async -> (image: CGImage, app: String)?
}

/// ScreenCaptureKit: the front app's topmost normal window, scaled to 1600 px wide so text stays readable, no cursor.
/// Unverified on a real display: it needs Screen Recording granted by the user, which an agent cannot do.
public struct SCKScreenGrabber: ScreenGrabber {
    public static let captureWidth = 1600
    public init() {}

    /// First normal-sized window of `pid` in a front-to-back window list (the shape CGWindowListCopyWindowInfo returns).
    static func topWindowID(pid: pid_t, stacking: [[String: Any]]) -> CGWindowID? {
        for w in stacking {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Width"] ?? 0) > 120, (b["Height"] ?? 0) > 80,
                  let n = w[kCGWindowNumber as String] as? UInt32 else { continue }
            return CGWindowID(n)
        }
        return nil
    }

    /// The system's window list is expensive to build and was rebuilt every 3 seconds. It is kept for a while and refreshed when the
    /// window being captured is not in it (a new window) or it has aged. Main-actor only, like every caller.
    @MainActor private static var cachedContent: (content: SCShareableContent, at: Date)?
    @MainActor private static func shareable(containing id: CGWindowID, size: CGSize?) async -> SCWindow? {
        // A window that was resized since the list was made is looked up again, so the picture is never the wrong shape.
        if let c = cachedContent, Date().timeIntervalSince(c.at) < 30,
           let w = c.content.windows.first(where: { $0.windowID == id }),
           size.map({ abs($0.width - w.frame.width) < 2 && abs($0.height - w.frame.height) < 2 }) ?? false { return w }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return nil }
        cachedContent = (content, Date())
        return content.windows.first(where: { $0.windowID == id })
    }

    static func boundsSize(of id: CGWindowID, stacking: [[String: Any]]) -> CGSize? {
        guard let w = stacking.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == id }),
              let b = w[kCGWindowBounds as String] as? [String: CGFloat], let width = b["Width"], let height = b["Height"] else { return nil }
        return CGSize(width: width, height: height)
    }

    public var isAllowed: Bool { CGPreflightScreenCaptureAccess() }
    public func requestAccess() { _ = CGRequestScreenCaptureAccess() }

    public func grab() async -> (image: CGImage, app: String)? {
        guard isAllowed, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() else { return nil }
        // The window the user is looking at is the topmost one of the front app, not its biggest: a browser with several windows
        // open must not be read through a bigger one hidden behind. CGWindowList is ordered front to back.
        let stacking = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let id = Self.topWindowID(pid: front.processIdentifier, stacking: stacking),
              let win = await Self.shareable(containing: id, size: Self.boundsSize(of: id, stacking: stacking)) else { return nil }
        let cfg = SCStreamConfiguration()
        let w = min(Self.captureWidth, Int(win.frame.width))
        cfg.width = w; cfg.height = max(1, Int(CGFloat(w) * win.frame.height / win.frame.width))
        cfg.showsCursor = false
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg) else { return nil }
        return (img, front.localizedName ?? "")
    }
}
