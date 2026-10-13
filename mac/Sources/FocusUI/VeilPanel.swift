import AppKit
import QuartzCore

/// One click-through window per display that drains the color from everything on screen, not only from Focus's own window.
/// A window-server backdrop layer samples what is behind the window and a saturation filter removes the color. Both are private
/// Core Animation classes (the same ones vibrancy uses), looked up by name; if either is missing the panel falls back to a plain gray wash,
/// which still mutes the screen but cannot remove color. A faint gray wash is also laid over the backdrop so the effect is visible either way.
/// Unverified on a real display: an agent cannot capture the screen. Settings has a Preview button to see it.
final class VeilPanel: NSPanel {
    private let backdrop: CALayer?
    private let filter: NSObject?
    private let wash = CALayer()

    var usesBackdrop: Bool { backdrop != nil && filter != nil }

    init() {
        var layer: CALayer?, f: NSObject?
        if let cls = NSClassFromString("CABackdropLayer") as? CALayer.Type, let fcls = NSClassFromString("CAFilter") as? NSObject.Type,
           let made = fcls.perform(NSSelectorFromString("filterWithType:"), with: "colorSaturate")?.takeUnretainedValue() as? NSObject {
            let b = cls.init()
            b.setValue(true, forKey: "windowServerAware")
            b.setValue("focus.veil", forKey: "groupName")
            made.setValue(1.0, forKey: "inputAmount")
            b.setValue([made], forKey: "filters")
            layer = b; f = made
        }
        backdrop = layer; filter = f
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        // Above windows and the Dock, below the notch panel (.statusBar) so a nudge there stays unveiled.
        level = .mainMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true; isMovable = false; hidesOnDeactivate = false
        let v = NSView(); v.wantsLayer = true
        wash.backgroundColor = NSColor(white: 0.42, alpha: 1).cgColor; wash.opacity = 0
        if let backdrop { v.layer!.addSublayer(backdrop) }
        v.layer!.addSublayer(wash)
        contentView = v
    }

    /// `percent` is 0 (no change) to 100 (fully gray).
    func apply(_ percent: Double) {
        let p = max(0, min(100, percent)) / 100
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let bounds = contentView?.bounds ?? .zero
        backdrop?.frame = bounds; wash.frame = bounds
        if let filter, let backdrop {
            filter.setValue(1 - p, forKey: "inputAmount")
            backdrop.setValue([filter], forKey: "filters")   // reassigned so the window server sees the new amount
        }
        // Full gray removes all color; the wash also darkens and flattens it so the top of the range is unmistakable.
        // Without the real filter the wash is all there is.
        wash.opacity = Float(p * (usesBackdrop ? 0.32 : 0.7))
        CATransaction.commit()
    }
}

/// Keeps one VeilPanel on every display and sets its gray from `SessionController.veilLevel()` ten times a second, so a fade is smooth.
/// The level itself ramps slowly (a percent or two a second), so a real drift fades in over a minute or more.
@MainActor
public final class VeilController {
    private let c: SessionController
    private var panels: [CGDirectDisplayID: VeilPanel] = [:]
    private var timer: Timer?
    public private(set) var lastLevel = 0.0
    private var shown = false

    public init(controller: SessionController) { self.c = controller }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
    }
    public func stop() { timer?.invalidate(); timer = nil; hide() }

    public var panelCountForTesting: Int { panels.values.filter { $0.isVisible }.count }
    public var usesBackdropForTesting: Bool { panels.values.first?.usesBackdrop ?? false }

    func update() {
        let level = c.veilLevel()
        lastLevel = level
        guard level >= 0.3 else { if shown { hide() }; return }
        shown = true
        let screens = NSScreen.screens
        var live = Set<CGDirectDisplayID>()
        for s in screens {
            let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            live.insert(id)
            let p = panels[id] ?? VeilPanel()
            panels[id] = p
            if p.frame != s.frame { p.setFrame(s.frame, display: false) }
            p.apply(level)
            p.orderFrontRegardless()
        }
        for (id, p) in panels where !live.contains(id) { p.orderOut(nil); panels[id] = nil }
    }

    private func hide() { shown = false; panels.values.forEach { $0.orderOut(nil) } }
}
