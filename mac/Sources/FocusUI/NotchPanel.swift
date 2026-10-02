import AppKit
import SwiftUI
import Observation

/// Hosts NotchView in a borderless panel at the top centre of the main screen, visible only while a session runs.
/// UNVERIFIED on a real display: placement, hover through a non-activating panel and the notch geometry have only been compiled,
/// not run. Spike S8 on a notched Mac decides whether this approach holds.
@MainActor
public final class NotchPanelController {
    private let c: SessionController
    private let openApp: () -> Void
    private var panel: NSPanel?
    private var running = false

    public init(controller: SessionController, openApp: @escaping () -> Void) { self.c = controller; self.openApp = openApp }

    public func start() { guard !running else { return }; running = true; track() }

    /// Re-run whenever what the notch shows changes: session on or off, the preference, or the nudge surface.
    private func track() {
        withObservationTracking {
            _ = c.isActive; _ = c.prefs.showNotch; _ = c.surface
        } onChange: { [weak self] in
            Task { @MainActor in self?.refresh(); self?.track() }
        }
        refresh()
    }

    private var host: NSHostingController<NotchView>?
    private var resizeObserver: NSObjectProtocol?

    func refresh() {
        guard c.isActive, c.prefs.showNotch, let screen = NSScreen.main else { panel?.orderOut(nil); return }
        let g = Self.geometry(screen)
        let view = NotchView(controller: c, notchWidth: g.width, notchHeight: g.height, openApp: openApp)
        let p = panel ?? makePanel()
        if let host { host.rootView = view } else {
            let h = NSHostingController(rootView: view)
            h.sizingOptions = [.preferredContentSize]       // the window follows the view: hover and nudges change its size
            host = h; p.contentViewController = h
        }
        recenter(p, screen)
        p.orderFrontRegardless()
        panel = p
    }

    /// Keep the panel centred under the top edge after every size change (a window grows from its top-left by default).
    func recenter(_ p: NSPanel, _ screen: NSScreen) {
        let size = p.frame.size
        let gap: CGFloat = Self.geometry(screen).width == 0 ? 6 : 0
        let target = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height - gap)
        if abs(p.frame.origin.x - target.x) > 0.5 || abs(p.frame.origin.y - target.y) > 0.5 { p.setFrameOrigin(target) }
    }

    func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isMovable = false; p.hidesOnDeactivate = false
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: p, queue: .main) { [weak self, weak p] _ in
            MainActor.assumeIsolated { if let self, let p, let screen = NSScreen.main { self.recenter(p, screen) } }
        }
        return p
    }

    /// Notch width and height in points; (0, 0) on a Mac without a notch.
    static func geometry(_ screen: NSScreen) -> (width: CGFloat, height: CGFloat) {
        let top = screen.safeAreaInsets.top
        guard top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else { return (0, 0) }
        return (screen.frame.width - l.width - r.width, top)
    }
}
