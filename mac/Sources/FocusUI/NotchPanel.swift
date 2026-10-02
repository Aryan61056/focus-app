import AppKit
import SwiftUI
import Observation

/// Hosts NotchView in a borderless panel at the top centre of a screen, visible only while a session runs.
/// The controller, not SwiftUI, decides the panel's frame (from NotchLayout), and it re-places the panel when displays change.
/// Two crashes found on a real notched Mac on 2026-10-01 (hover, and unplugging a monitor) came from SwiftUI sizing this window;
/// both are the same AppKit layout loop, and tests now drive hover and screen changes. Placement and hover on a real display
/// are still only checked by those tests, not by eye.
@MainActor
public final class NotchPanelController {
    private let c: SessionController
    private let openApp: () -> Void
    private let model = NotchModel()
    private var panel: NSPanel?
    private var running = false
    private var screenObserver: NSObjectProtocol?

    public init(controller: SessionController, openApp: @escaping () -> Void) { self.c = controller; self.openApp = openApp }

    public var isShowing: Bool { panel?.isVisible ?? false }
    var frameForTesting: NSRect? { panel?.frame }
    /// For tests: pretend the pointer moved onto or off the notch.
    public func setHoverForTesting(_ on: Bool) { model.hover = on }

    public func start() {
        guard !running else { return }
        running = true
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        track()
    }

    public func stop() {
        running = false
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        panel?.orderOut(nil)
    }

    /// Re-run whenever what the notch shows changes: session on or off, the preference, the nudge surface, or hover.
    private func track() {
        guard running else { return }
        withObservationTracking {
            _ = c.isActive; _ = c.prefs.showNotch; _ = c.surface; _ = model.hover
        } onChange: { [weak self] in
            // Hop off the observation callback, then apply on the next turn of the run loop, never inside a layout pass.
            Task { @MainActor in self?.refresh(); self?.track() }
        }
    }

    /// Notch width and height in points; (0, 0) on a Mac without a notch (or with no screen at all).
    static func geometry(_ screen: NSScreen) -> (width: CGFloat, height: CGFloat) {
        let top = screen.safeAreaInsets.top
        guard top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else { return (0, 0) }
        let w = screen.frame.width - l.width - r.width
        return w > 0 ? (w, top) : (0, 0)
    }

    func refresh() {
        guard running, c.isActive, c.prefs.showNotch, let screen = NSScreen.main ?? NSScreen.screens.first else { panel?.orderOut(nil); return }
        let g = Self.geometry(screen)
        let mode = NotchView.mode(for: c, hover: model.hover)
        let size = NotchLayout.size(mode, notchWidth: g.width, notchHeight: g.height)
        let gap: CGFloat = g.width == 0 ? 6 : 0
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height - gap, width: size.width, height: size.height)

        let p = panel ?? makePanel()
        // A fresh hosting view each time the geometry changes (a display was added or removed); the same one otherwise.
        let view = NotchView(controller: c, notchWidth: g.width, notchHeight: g.height, model: model, openApp: openApp)
        if let host = p.contentView as? NSHostingView<NotchView> { host.rootView = view } else {
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []              // SwiftUI must not size the window
            host.safeAreaRegions = []            // the window touches the top of a notched screen; ignore that safe area
            p.contentView = host
        }
        if p.frame != frame { p.setFrame(frame, display: true, animate: false) }
        p.orderFrontRegardless()
        panel = p
    }

    func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isMovable = false; p.hidesOnDeactivate = false
        return p
    }
}
