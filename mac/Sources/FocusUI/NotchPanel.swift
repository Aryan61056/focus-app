import AppKit
import SwiftUI
import Observation

/// Content view that reports the pointer entering and leaving, even while Focus is not the active app. SwiftUI's own hover does not fire
/// for a panel of a background app, and a notch that only reacts when Focus is in front would never open.
final class HoverBox: NSView {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(a); area = a
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// Hosts NotchView in borderless panels, visible only while a session runs.
/// The controller, not SwiftUI, decides each panel's frame (from NotchLayout), and it re-places panels when displays change.
/// Two crashes found on a real notched Mac on 2026-10-01 (hover, and unplugging a monitor) came from SwiftUI sizing this window;
/// both are the same AppKit layout loop, and tests now drive hover and screen changes.
///
/// With more than one display the resting ring stays on one "home" screen: the notched built-in display if there is one (so it
/// sits in the hardware notch), else the primary screen. NSScreen.main is not used: it follows the key window and would make
/// the ring jump between displays. A nudge also shows on the screen the pointer is on, so it reaches you where you are working.
@MainActor
public final class NotchPanelController {
    private struct Slot { let panel: NSPanel; let model: NotchModel }

    private let c: SessionController
    private let openApp: () -> Void
    private var slots: [CGDirectDisplayID: Slot] = [:]
    private var homeID: CGDirectDisplayID?
    private var running = false
    private var screenObserver: NSObjectProtocol?

    public init(controller: SessionController, openApp: @escaping () -> Void) { self.c = controller; self.openApp = openApp }

    public var isShowing: Bool { slots.values.contains { $0.panel.isVisible } }
    var frameForTesting: NSRect? { homeID.flatMap { slots[$0] }?.panel.frame }
    var framesForTesting: [NSRect] { slots.values.filter { $0.panel.isVisible }.map { $0.panel.frame } }
    /// For tests: pretend the pointer moved onto or off the notch of the home screen.
    public func setHoverForTesting(_ on: Bool) { homeID.flatMap { slots[$0] }?.model.hover = on }

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
        slots.values.forEach { $0.panel.orderOut(nil) }
    }

    /// Re-run whenever what the notch shows changes: session on or off, the preference, the nudge surface, or hover on any panel.
    private func track() {
        guard running else { return }
        withObservationTracking {
            _ = c.isActive; _ = c.prefs.showNotch; _ = c.surface
            for slot in slots.values { _ = slot.model.hover }
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

    /// Which screen keeps the resting ring: the first one with a hardware notch, else the first (the primary screen, which has the menu bar).
    static func homeIndex(notchWidths: [CGFloat]) -> Int? {
        notchWidths.isEmpty ? nil : (notchWidths.firstIndex { $0 > 0 } ?? 0)
    }

    private static func id(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    func refresh() {
        // The notch preference is about the resting ring. A nudge always shows here, so it reaches you when Focus is in the background.
        let nudging = c.surface.map { $0.kind != "gate" } ?? false
        let screens = NSScreen.screens
        guard running, c.isActive, c.prefs.showNotch || nudging,
              let hi = Self.homeIndex(notchWidths: screens.map { Self.geometry($0).width }) else { hideAll(); return }
        let home = screens[hi]
        var targets = [home]
        if nudging, let here = screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }), Self.id(here) != Self.id(home) { targets.append(here) }
        homeID = Self.id(home)

        let wanted = Set(targets.map(Self.id))
        for (key, slot) in slots where !wanted.contains(key) { slot.panel.orderOut(nil); if key != homeID { slots[key] = nil } }
        for screen in targets { place(on: screen) }
    }

    private func hideAll() { slots.values.forEach { $0.panel.orderOut(nil) } }

    private func place(on screen: NSScreen) {
        let key = Self.id(screen)
        let slot = slots[key] ?? Slot(panel: makePanel(), model: NotchModel())
        slots[key] = slot
        let p = slot.panel
        let g = Self.geometry(screen)
        let mode = NotchView.mode(for: c, hover: slot.model.hover)
        let size = NotchLayout.size(mode, notchWidth: g.width, notchHeight: g.height)
        // A notched screen: flush with the top edge, around the hardware notch. Any other screen: a pill a few points under the menu bar
        // (visibleFrame starts below it), never on top of the menu bar's items.
        let top = g.width == 0 ? screen.visibleFrame.maxY - 6 : screen.frame.maxY
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)

        // A fresh root view each time the geometry changes (a display was added or removed); the same hosting view otherwise.
        let view = NotchView(controller: c, notchWidth: g.width, notchHeight: g.height, model: slot.model, openApp: openApp)
        if let host = p.contentView?.subviews.first as? NSHostingView<NotchView> { host.rootView = view } else {
            // The hosting view is NOT the window's content view. As the content view it resizes the window from inside AppKit's
            // constraint pass and throws when its own state changes there (the hover crash, reproduced with synthetic mouse moves).
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            host.safeAreaRegions = []
            let box = HoverBox(frame: NSRect(origin: .zero, size: frame.size))
            let model = slot.model
            box.onHover = { on in model.hover = on }
            host.frame = box.bounds; host.autoresizingMask = [.width, .height]
            box.addSubview(host)
            p.contentView = box
        }
        if p.frame != frame { p.setFrame(frame, display: true, animate: false) }
        p.orderFrontRegardless()
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
