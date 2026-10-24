import AppKit
import QuartzCore

/// One click-through window per display that drains the color from everything on screen, not only from Hushd's own window.
/// A window-server backdrop layer samples what is behind the window and a saturation filter removes the color. Both are private
/// Core Animation classes (the same ones vibrancy uses), looked up by name; if either is missing the panel falls back to a plain gray wash,
/// which still mutes the screen but cannot remove color. A faint gray wash is also laid over the backdrop so the effect is visible either way.
/// Unverified on a real display: an agent cannot capture the screen. Settings has a Preview button to see it.
/// The shape of the closing-in edges for a level of 0 to 100 (the same ramp as the gray). Pure, so it is tested.
/// `clearUntil` is how far from the middle (0) toward the middle of an edge (1) the screen stays untouched; `edgeAlpha` is how dark the edge gets.
/// At the top the middle 40 percent stays clear and the edges are 72 percent dark, so the work in the middle stays readable and the room goes dim.
public enum Vignette {
    /// Blur radius in points for a fog level of 0 to 100. Soft at the start, at the top the screen can be made out but not read.
    public static func fogRadius(_ percent: Double) -> Double { percent > 0 ? 0.5 + 0.14 * min(100, percent) : 0 }
    public static func shape(_ percent: Double) -> (clearUntil: Double, edgeAlpha: Double) {
        let p = max(0, min(100, percent)) / 100
        return (0.86 - 0.46 * p, 0.72 * p)
    }
}

final class VeilPanel: NSPanel {
    private let backdrop: CALayer?
    private let filter: NSObject?
    /// The second filter on the same backdrop: a blur for "fog". Nil when the window server's filter classes are missing.
    private let blur: NSObject?
    private let wash = CALayer()
    private let edges = CAGradientLayer()

    var usesBackdrop: Bool { backdrop != nil && filter != nil }
    var usesBlur: Bool { usesBackdrop && blur != nil }
    private var gray = 0.0, fog = 0.0

    init() {
        var layer: CALayer?, f: NSObject?, bl: NSObject?
        if let cls = NSClassFromString("CABackdropLayer") as? CALayer.Type, let fcls = NSClassFromString("CAFilter") as? NSObject.Type,
           let made = fcls.perform(NSSelectorFromString("filterWithType:"), with: "colorSaturate")?.takeUnretainedValue() as? NSObject {
            let b = cls.init()
            b.setValue(true, forKey: "windowServerAware")
            b.setValue("focus.veil", forKey: "groupName")
            made.setValue(1.0, forKey: "inputAmount")
            b.setValue([made], forKey: "filters")
            layer = b; f = made
            if let fcls2 = NSClassFromString("CAFilter") as? NSObject.Type, let blurFilter = fcls2.perform(NSSelectorFromString("filterWithType:"), with: "gaussianBlur")?.takeUnretainedValue() as? NSObject {
                blurFilter.setValue(0.0, forKey: "inputRadius")
                bl = blurFilter
            }
        }
        backdrop = layer; filter = f; blur = bl
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        // Above windows and the Dock, below the notch panel (.statusBar) so a nudge there stays unveiled.
        level = .mainMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true; isMovable = false; hidesOnDeactivate = false
        canHide = false   // hiding Hushd does not lift the gray
        let v = NSView(); v.wantsLayer = true
        wash.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor; wash.opacity = 0
        edges.type = .radial; edges.startPoint = CGPoint(x: 0.5, y: 0.5); edges.endPoint = CGPoint(x: 1, y: 1); edges.opacity = 0
        if let backdrop { v.layer!.addSublayer(backdrop) }
        v.layer!.addSublayer(wash)
        v.layer!.addSublayer(edges)
        contentView = v
    }

    /// `percent` is 0 (open) to 100 (the edges as dark as they get).
    func applyEdges(_ percent: Double) {
        let (clear, alpha) = Vignette.shape(percent)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        edges.frame = contentView?.bounds ?? .zero
        edges.opacity = percent < 0.3 ? 0 : 1
        let dark = { (a: Double) in NSColor(srgbRed: 0.03, green: 0.03, blue: 0.05, alpha: a).cgColor }
        // An in-between stop keeps the fall-off soft instead of a visible ring.
        let mid = (clear + 1) / 2
        edges.colors = [dark(0), dark(0), dark(alpha * 0.4), dark(alpha)]
        edges.locations = [0, NSNumber(value: clear), NSNumber(value: mid), 1]
        CATransaction.commit()
    }

    /// `percent` is 0 (no change) to 100 (fully gray).
    func apply(_ percent: Double) { gray = percent; render() }

    /// `percent` is 0 (no change) to 100 (the most fog: the screen blurred so that it can be made out but not read).
    func applyFog(_ percent: Double) { fog = percent; render() }

    private func render() {
        let p = max(0, min(100, gray)) / 100, f = max(0, min(100, fog)) / 100
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let bounds = contentView?.bounds ?? .zero
        backdrop?.frame = bounds; wash.frame = bounds
        if let filter, let backdrop {
            filter.setValue(1 - p, forKey: "inputAmount")
            var list: [NSObject] = [filter]
            if let blur, f > 0.003 { blur.setValue(Vignette.fogRadius(fog), forKey: "inputRadius"); list.append(blur) }
            backdrop.setValue(list, forKey: "filters")   // reassigned so the window server sees the new amounts
        }
        // Full gray removes all color; the wash also darkens and flattens it so the top of the range is unmistakable.
        // Without the real filter the wash is all there is. Fog without the filter falls back to a pale veil.
        let grayWash = p * (usesBackdrop ? 0.62 : 0.85)
        let fogWash = usesBlur ? 0.0 : f * 0.5
        wash.opacity = Float(max(grayWash, fogWash))
        CATransaction.commit()
    }
}

/// Keeps one VeilPanel on every display and sets its gray from `SessionController.veilLevel()` ten times a second, so a fade is smooth.
/// The level itself ramps slowly (a percent or two a second), so a real drift fades in over a minute or more.
@MainActor
public final class VeilController {
    private let c: SessionController
    private var panels: [CGDirectDisplayID: VeilPanel] = [:]
    /// The one panel for "gray only the window you drifted into".
    private var windowPanel: VeilPanel?
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
    public var windowPanelFrameForTesting: NSRect? { windowPanel.flatMap { $0.isVisible ? $0.frame : nil } }
    public var usesBackdropForTesting: Bool { panels.values.first?.usesBackdrop ?? false }

    func update() {
        let level = c.veilLevel(), edge = c.edgeLevel(), fogLevel = c.fogLevel()
        lastLevel = level
        // Gray and fog on every display, or only on the window you drifted into (then the edges, if on, still close in on every display).
        var screenGray = 0.0, windowGray = 0.0, screenFog = 0.0, windowFog = 0.0, windowRect: CGRect?
        // The front window's frame is a window-list query: asked only when there is gray or fog to place, not ten times a second at rest.
        let needsFrame = c.prefs.grayWindowOnly && (level >= 0.3 || fogLevel >= 0.3)
        switch c.veilRegion(windowFrame: needsFrame ? c.frontWindowFrame?() : nil) {
        case .screens: screenGray = level; screenFog = fogLevel
        case .window(let r): windowGray = level; windowFog = fogLevel; windowRect = r
        case .none: break
        }
        guard screenGray >= 0.3 || windowGray >= 0.3 || screenFog >= 0.3 || windowFog >= 0.3 || edge >= 0.3 else { if shown { hide() }; return }
        shown = true
        let screens = NSScreen.screens
        var live = Set<CGDirectDisplayID>()
        for s in screens {
            let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            live.insert(id)
            let p = panels[id] ?? VeilPanel()
            panels[id] = p
            if p.frame != s.frame { p.setFrame(s.frame, display: false) }
            p.apply(screenGray); p.applyFog(screenFog)
            p.applyEdges(edge)
            p.orderFrontRegardless()
        }
        for (id, p) in panels where !live.contains(id) { p.orderOut(nil); panels[id] = nil }
        if windowGray >= 0.3 || windowFog >= 0.3, let r = windowRect, let primary = screens.first {
            let w = windowPanel ?? VeilPanel(); windowPanel = w
            let target = CueLayout.cocoaRect(fromCG: r, primaryHeight: primary.frame.height)
            if w.frame != target { w.setFrame(target, display: false) }
            w.apply(windowGray); w.applyFog(windowFog); w.applyEdges(0)
            w.orderFrontRegardless()
        } else { windowPanel?.orderOut(nil) }
    }

    private func hide() { shown = false; panels.values.forEach { $0.orderOut(nil) }; windowPanel?.orderOut(nil) }
}
