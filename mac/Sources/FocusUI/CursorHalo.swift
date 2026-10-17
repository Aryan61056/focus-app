import AppKit
import QuartzCore

/// The pointer halo: a ring around the mouse that grows the longer you are off task (the same ramp as the gray and the closing edges). It is
/// hard to miss and covers nothing; it is click-through, never takes focus, and is gone when you are back. Off by default. It follows the
/// pointer by looking at where it is 30 times a second while it is showing, and only twice a second the rest of the time to see whether it
/// should start.
/// Its cost while showing has not been measured against the 2 percent budget (PLAN section 9).
public enum Halo {
    /// Ring radius in points for a level of 0 to 100: small enough at the start to be a hint, large enough at the top to be unmissable.
    public static func radius(_ percent: Double) -> Double { 20 + 0.9 * max(0, min(100, percent)) }
    /// How strong the ring is, 0 to 1, so it appears gently.
    public static func opacity(_ percent: Double) -> Double { percent < 3 ? 0 : 0.25 + 0.4 * min(percent, 100) / 100 }
    /// Below this the ring is not shown at all.
    public static let showFrom = 3.0
}

final class HaloPanel: NSPanel {
    let ring = CALayer()
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 240, height: 240), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true; isMovable = false; hidesOnDeactivate = false; canHide = false
        let v = NSView(); v.wantsLayer = true
        ring.borderWidth = 2.5
        v.layer!.addSublayer(ring)
        contentView = v
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(radius: Double, opacity: Double, around p: NSPoint) {
        let size = ceil(radius * 2 + 8)
        let color = NSColor(Tokens.accent).cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        setFrame(NSRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size), display: false)
        ring.frame = NSRect(x: 4, y: 4, width: radius * 2, height: radius * 2)
        ring.cornerRadius = radius; ring.borderColor = color; ring.opacity = Float(opacity)
        CATransaction.commit()
    }
}

@MainActor
public final class HaloController {
    private let c: SessionController
    private var panel: HaloPanel?
    private var timer: Timer?
    private var level = 0.0
    private var sinceLevelCheck = 0
    var pointer: () -> NSPoint = { NSEvent.mouseLocation }

    public init(controller: SessionController) { self.c = controller }
    public var isShowing: Bool { panel?.isVisible ?? false }
    var frameForTesting: NSRect? { panel?.frame }

    /// True while following the pointer (30 times a second); false while only waiting (twice a second).
    private(set) var isFast = false

    public func start() { guard timer == nil else { return }; schedule(fast: false) }
    public func stop() { timer?.invalidate(); timer = nil; hide() }

    private func schedule(fast: Bool) {
        timer?.invalidate()
        isFast = fast
        timer = Timer.scheduledTimer(withTimeInterval: fast ? 1.0 / 30 : 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
    }

    /// The level is asked for about 5 times a second while showing; the position every tick.
    func update() {
        sinceLevelCheck += 1
        if sinceLevelCheck >= 6 || !isFast { sinceLevelCheck = 0; level = c.haloLevel() }
        guard level >= Halo.showFrom else { hide(); return }
        if !isFast { schedule(fast: true) }
        let p = panel ?? HaloPanel(); panel = p
        p.apply(radius: Halo.radius(level), opacity: Halo.opacity(level), around: pointer())
        if !p.isVisible { p.orderFrontRegardless() }
    }

    private func hide() {
        level = 0; panel?.orderOut(nil)
        if isFast, timer != nil { schedule(fast: false) }
    }
}
