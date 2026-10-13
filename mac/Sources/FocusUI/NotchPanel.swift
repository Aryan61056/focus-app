import AppKit
import SwiftUI
import Observation

/// Content view that reports the pointer entering and leaving the visible black shape, even while Focus is not the active app.
/// SwiftUI's own hover does not fire for a panel of a background app, and a notch that only reacts when Focus is in front would
/// never open. The window is bigger than the shape (see NotchLayout.panelSize), so the tracking rect follows `visibleSize`, not the
/// window. Opening waits a moment so the pointer passing over the menu bar does not pop the notch open; closing waits less.
final class HoverBox: NSView {
    var onHover: ((Bool) -> Void)?
    var openDelay: TimeInterval = 0.16, closeDelay: TimeInterval = 0.1
    /// The shape's current size, centred at the top of the window. Set by the controller whenever the mode changes.
    var visibleSize = CGSize.zero { didSet { if oldValue != visibleSize { updateTrackingAreas(); syncSoon() } } }
    private var area: NSTrackingArea?
    private var inside = false
    private var pending: DispatchWorkItem?

    var visibleRect2: NSRect {
        let w = min(bounds.width, visibleSize.width), h = min(bounds.height, visibleSize.height)
        return NSRect(x: (bounds.width - w) / 2, y: bounds.height - h, width: w, height: h)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: visibleRect2, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(a); area = a
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateTrackingAreas() }
    override func mouseEntered(with event: NSEvent) { set(true) }
    override func mouseExited(with event: NSEvent) { set(false) }

    private func set(_ on: Bool) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.inside != on else { return }
            self.inside = on; self.onHover?(on)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (on ? openDelay : closeDelay), execute: work)
    }

    /// When the shape resizes under a stationary pointer AppKit sends no enter or exit; compare with where the pointer really is.
    private func syncSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.window else { return }
            let p = self.convert(w.mouseLocationOutsideOfEventStream, from: nil)
            let now = self.visibleRect2.contains(p) && w.isVisible
            if now != self.inside { self.set(now) }
        }
    }
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
    private var slots: [CGDirectDisplayID: Slot] = [:]
    private var homeID: CGDirectDisplayID?
    private var running = false
    private var screenObserver: NSObjectProtocol?

    public init(controller: SessionController) { self.c = controller }

    public var isShowing: Bool { slots.values.contains { $0.panel.isVisible } }
    var frameForTesting: NSRect? { homeID.flatMap { slots[$0] }?.panel.frame }
    /// The size of the black shape (what the user sees), as opposed to the fixed window around it.
    var shownSizeForTesting: CGSize? { (homeID.flatMap { slots[$0] }?.panel.contentView as? HoverBox)?.visibleSize }
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
            _ = c.isActive; _ = c.prefs.showNotch; _ = c.surface; _ = c.checkIn; _ = c.rhythmPrompt
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
        let nudging = (c.surface.map { $0.kind != "gate" } ?? false) || c.checkIn != nil || c.rhythmPrompt != nil
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
        let size = NotchLayout.panelSize(notchWidth: g.width, notchHeight: g.height)
        let shown = NotchLayout.size(mode, notchWidth: g.width, notchHeight: g.height)
        // A notched screen: flush with the top edge, around the hardware notch. Any other screen: a pill a few points under the menu bar
        // (visibleFrame starts below it), never on top of the menu bar's items.
        let top = g.width == 0 ? screen.visibleFrame.maxY - 6 : screen.frame.maxY
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)

        // A fresh root view each time the geometry changes (a display was added or removed); the same hosting view otherwise.
        let view = NotchView(controller: c, notchWidth: g.width, notchHeight: g.height, model: slot.model)
        if let host = p.contentView?.subviews.first as? NSHostingView<NotchView> { host.rootView = view } else {
            // The hosting view is NOT the window's content view. As the content view it resizes the window from inside AppKit's
            // constraint pass and throws when its own state changes there (the hover crash, reproduced with synthetic mouse moves).
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            host.safeAreaRegions = []
            let box = HoverBox(frame: NSRect(origin: .zero, size: frame.size))
            let model = slot.model
            box.onHover = { on in model.hover = on }
            box.visibleSize = shown
            host.frame = box.bounds; host.autoresizingMask = [.width, .height]
            box.addSubview(host)
            p.contentView = box
        }
        if p.frame != frame { p.setFrame(frame, display: true, animate: false) }
        (p.contentView as? HoverBox)?.visibleSize = shown
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
