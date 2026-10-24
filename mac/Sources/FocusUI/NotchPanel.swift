import AppKit
import SwiftUI
import Observation

/// Content view that reports the pointer entering and leaving the visible black shape, even while Hushd is not the active app.
/// SwiftUI's own hover does not fire for a panel of a background app, and a notch that only reacts when Hushd is in front would
/// never open. The window is bigger than the shape (see NotchLayout.panelSize), so the tracking rect follows `visibleSize`, not the
/// window. Opening waits a moment so the pointer passing over the menu bar does not pop the notch open; closing waits less.
final class HoverBox: NSView {
    var onHover: ((Bool) -> Void)?
    /// A file drag is over the panel (true) or has left or landed (false).
    var onDropHover: ((Bool) -> Void)?
    /// Files dropped on the notch.
    var onFiles: (([URL]) -> Void)?
    /// Droppy waits about 0.2 s before it reacts to the pointer and about 0.25 s before it closes; these match.
    var openDelay: TimeInterval = 0.2, closeDelay: TimeInterval = 0.24
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
        let a = NSTrackingArea(rect: visibleRect2, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(a); area = a
    }

    // MARK: files dropped on the notch
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); registerForDraggedTypes([.fileURL]) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { onDropHover?(true); return .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDropHover?(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onFiles?(urls)
        // The pointer is on the notch now: treat it as a hover, so the open tray stays until the pointer leaves.
        set(true)
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { onDropHover?(false) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateTrackingAreas() }
    override func mouseEntered(with event: NSEvent) { set(true) }
    override func mouseExited(with event: NSEvent) { set(false) }

    // MARK: click-through
    // The window is as big as the biggest mode (see NotchLayout.panelSize), so most of it is empty. A window gets every click inside its
    // frame, whatever is drawn there, which made menu bar items next to the notch and a browser's tab bar unclickable for a whole
    // session. So it ignores the mouse except while the pointer is on the shape, found by watching the pointer system-wide.
    private var monitors: [Any] = []
    private var wanted = false

    func startMonitoring() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in MainActor.assumeIsolated { self?.pointerMoved() } }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in MainActor.assumeIsolated { self?.pointerMoved() }; return e }) { monitors.append(l) }
        pointerMoved()
    }

    func stopMonitoring() {
        monitors.forEach { NSEvent.removeMonitor($0) }; monitors = []
        pending?.cancel(); pending = nil; pendingOn = nil; wanted = false; inside = false; poll?.invalidate(); poll = nil
    }

    /// Tests pin the pointer here so the real one cannot interfere.
    var pointerForTesting: NSPoint?
    /// Where the pointer is, in this view's coordinates.
    func pointerInView() -> NSPoint? {
        guard let w = window else { return nil }
        return convert(w.convertPoint(fromScreen: pointerForTesting ?? NSEvent.mouseLocation), from: nil)
    }

    /// The shape in screen coordinates.
    func shapeOnScreen() -> NSRect? {
        guard let w = window else { return nil }
        return w.convertToScreen(convert(visibleRect2, to: nil))
    }

    /// Exposed so tests can drive it. The window takes clicks only while the pointer is on the shape, and that is also what opens and closes it.
    func pointerMoved(at point: NSPoint? = nil) {
        let p = point ?? pointerForTesting ?? NSEvent.mouseLocation
        guard let w = window, w.isVisible, let shape = shapeOnScreen() else { return }
        let on = shape.insetBy(dx: -2, dy: -2).contains(p)
        if w.ignoresMouseEvents == on { w.ignoresMouseEvents = !on }
        if on != wanted { set(on) }
    }

    private var pendingOn: Bool?

    private func set(_ on: Bool) {
        // Asking again for what is already about to happen must not restart its delay. The safety-net poll asks every 0.12 s to close,
        // which is shorter than the 0.24 s close delay, so each ask cancelled the last and the notch never collapsed.
        if pendingOn == on, pending != nil { return }
        wanted = on
        pending?.cancel(); pendingOn = on
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil; self.pendingOn = nil
            // Closing always runs, even when the open never did: a click inside the open delay (0.2 s) expands the card before `inside`
            // flips, and skipping the close then left it open for good.
            if on, self.inside { return }
            self.inside = on; self.onHover?(on)
            self.watch(on)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (on ? openDelay : closeDelay), execute: work)
    }

    /// Another app's window over the notch (Droppy, NotchNook and the like sit there too) can swallow the exit, which left the notch
    /// stuck open. While it is open, check where the pointer really is a few times a second and close it once the pointer is gone.
    private var poll: Timer?
    private func watch(_ on: Bool) {
        poll?.invalidate(); poll = nil
        guard on else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.pointerInView() else { return }
                if !self.visibleRect2.insetBy(dx: -2, dy: -2).contains(p) { self.set(false) }
            }
        }
    }

    /// When the shape resizes under a stationary pointer AppKit sends no enter or exit; compare with where the pointer really is.
    private func syncSoon() {
        // The shape changed under a resting pointer: decide again whether the window should take clicks, and whether this is a hover.
        DispatchQueue.main.async { [weak self] in self?.pointerMoved() }
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
    /// Panels tucking back into the notch, ordered out when the tuck finishes unless they are wanted again first.
    private var tucking: [CGDirectDisplayID: DispatchWorkItem] = [:]
    /// How long the tuck runs before the panel is ordered out: Motion.notchTuck settles in about this.
    static let tuckSeconds: TimeInterval = 0.36

    public init(controller: SessionController) { self.c = controller }

    /// Showing means meant to be seen: a panel still tucking away after its session ended does not count.
    public var isShowing: Bool { slots.contains { $0.value.panel.isVisible && tucking[$0.key] == nil } }
    var frameForTesting: NSRect? { homeID.flatMap { slots[$0] }?.panel.frame }
    /// The size of the black shape (what the user sees), as opposed to the fixed window around it.
    var shownSizeForTesting: CGSize? { (homeID.flatMap { slots[$0] }?.panel.contentView as? HoverBox)?.visibleSize }
    var modelForTesting: NotchModel? { homeID.flatMap { slots[$0] }?.model }
    var hoverBoxForTesting: HoverBox? { homeID.flatMap { slots[$0] }?.panel.contentView as? HoverBox }
    var panelForTesting: NSPanel? { homeID.flatMap { slots[$0] }?.panel }
    var framesForTesting: [NSRect] { slots.filter { $0.value.panel.isVisible && tucking[$0.key] == nil }.map { $0.value.panel.frame } }
    /// Any panel window still on screen, including one tucking away.
    var anyWindowVisibleForTesting: Bool { slots.values.contains { $0.panel.isVisible } }
    /// For tests: pretend the pointer moved onto or off the notch of the home screen.
    public func setHoverForTesting(_ on: Bool) { homeID.flatMap { slots[$0] }?.model.hover = on }
    /// For tests and the scripted demo: pretend the notch of the home screen was clicked open, or closed.
    public func setExpandedForTesting(_ on: Bool) { homeID.flatMap { slots[$0] }?.model.expanded = on }
    /// For tests and the scripted demo: pretend a file drag is over the notch of the home screen.
    public func setDropTargetedForTesting(_ on: Bool) { homeID.flatMap { slots[$0] }?.model.dropTargeted = on }
    /// For the scripted demo: switch the open notch to one of its pages.
    public func setTabForTesting(_ tab: NotchTab) { homeID.flatMap { slots[$0] }?.model.tab = tab }

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
        tucking.values.forEach { $0.cancel() }; tucking = [:]
        slots.values.forEach { ($0.panel.contentView as? HoverBox)?.stopMonitoring(); $0.panel.orderOut(nil); $0.model.presented = false }
    }

    /// Re-run whenever what the notch shows changes: session on or off, the preference, the nudge surface, or hover on any panel.
    private func track() {
        guard running else { return }
        withObservationTracking {
            _ = c.isActive; _ = c.prefs.showNotch; _ = c.prefs.showBanner; _ = c.surface; _ = c.checkIn; _ = c.rhythmPrompt
            for slot in slots.values { _ = slot.model.hover; _ = slot.model.expanded; _ = slot.model.dropTargeted }
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
        // The notch preference is about the resting ring. With the banner off, a nudge shows here even so, so it still reaches you.
        let nudging = NotchView.opensToNudge(c)
        let screens = NSScreen.screens
        guard running, c.isActive, c.prefs.showNotch || nudging,
              let hi = Self.homeIndex(notchWidths: screens.map { Self.geometry($0).width }) else { hideAll(); return }
        let home = screens[hi]
        var targets = [home]
        if nudging, let here = screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }), Self.id(here) != Self.id(home) { targets.append(here) }
        homeID = Self.id(home)

        let wanted = Set(targets.map(Self.id))
        for key in slots.keys where !wanted.contains(key) { tuck(key) }
        for screen in targets { place(on: screen) }
    }

    private func hideAll() { for key in slots.keys { tuck(key) } }

    /// The shape shrinks back into the hardware notch, then the panel goes. A panel on a screen that is not home is dropped after.
    private func tuck(_ key: CGDirectDisplayID) {
        guard let slot = slots[key], slot.panel.isVisible, tucking[key] == nil else { return }
        slot.model.presented = false; slot.model.expanded = false
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.tucking[key] = nil
            (slot.panel.contentView as? HoverBox)?.stopMonitoring()
            slot.panel.orderOut(nil)
            if key != self.homeID { self.slots[key] = nil }
        }
        tucking[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tuckSeconds, execute: work)
    }

    private func place(on screen: NSScreen) {
        let key = Self.id(screen)
        let slot = slots[key] ?? Slot(panel: makePanel(), model: NotchModel())
        slots[key] = slot
        let p = slot.panel
        let g = Self.geometry(screen)
        let mode = NotchView.mode(for: c, hover: slot.model.hover, expanded: slot.model.expanded, dropping: slot.model.dropTargeted)
        let size = NotchLayout.panelSize(notchWidth: g.width, notchHeight: g.height)
        let shown = NotchLayout.hitSize(mode, notchWidth: g.width, notchHeight: g.height)
        // A notched screen: flush with the top edge, around the hardware notch. Any other screen: a pill a few points under the menu bar
        // (visibleFrame starts below it), never on top of the menu bar's items.
        let top = g.width == 0 ? screen.visibleFrame.maxY - 6 : screen.frame.maxY
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)

        // A fresh root view each time the geometry changes (a display was added or removed); the same hosting view otherwise.
        let view = NotchView(controller: c, notchWidth: g.width, notchHeight: g.height, model: slot.model, tray: NotchTray.shared)
        if let host = p.contentView?.subviews.first as? NSHostingView<NotchView> { host.rootView = view } else {
            // The hosting view is NOT the window's content view. As the content view it resizes the window from inside AppKit's
            // constraint pass and throws when its own state changes there (the hover crash, reproduced with synthetic mouse moves).
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            host.safeAreaRegions = []
            let box = HoverBox(frame: NSRect(origin: .zero, size: frame.size))
            let model = slot.model
            // Leaving closes a card a click opened, as Droppy's does.
            box.onHover = { on in model.hover = on; if !on { model.expanded = false } }
            box.onDropHover = { on in model.dropTargeted = on }
            box.onFiles = { urls in NotchTray.shared.add(urls); model.expanded = true }
            box.visibleSize = shown
            host.frame = box.bounds; host.autoresizingMask = [.width, .height]
            box.addSubview(host)
            p.contentView = box
        }
        if p.frame != frame { p.setFrame(frame, display: true, animate: false) }
        (p.contentView as? HoverBox)?.visibleSize = shown
        tucking.removeValue(forKey: key)?.cancel()   // wanted again mid-tuck: grow back out from wherever it got to
        let arriving = !p.isVisible
        if arriving { p.ignoresMouseEvents = true }   // click-through until the pointer is on the shape (HoverBox.pointerMoved)
        p.orderFrontRegardless()
        (p.contentView as? HoverBox)?.startMonitoring()
        if arriving {
            // Draw one frame tucked inside the notch, then grow out of it. Setting it in the same turn would skip the animation.
            slot.model.presented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                guard let self, self.running, self.tucking[key] == nil else { return }
                slot.model.presented = true
            }
        } else {
            slot.model.presented = true
        }
    }

    func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isMovable = false; p.hidesOnDeactivate = false
        // Hiding Hushd (Command-H, or Hide Others from another app) hid the notch and every nudge in it for the rest of the session.
        p.canHide = false
        return p
    }
}
