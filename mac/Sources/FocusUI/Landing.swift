import AppKit
import Observation

// The landing cue: after "Back to task", a soft ring around the window you land in, so your eye knows where the task is without searching
// a screen full of windows. It is a reward, not a nudge: it only follows a trip back, it never asks for anything, and it is gone in about
// a second and a half. Click-through, never takes focus, and no motion at all with Reduce Motion on.

public enum Landing {
    public enum Style: Equatable, Sendable {
        case none
        /// The exact window or tab was raised: a full ring.
        case exact
        /// Only the app came forward, so the ring is lighter: it marks the window in front without claiming it is the very one.
        case approximate
        /// While you are away: a faint ring on the window Back to task would take you to, so the way back is visible.
        case beacon
    }

    public static func style(for outcome: ReturnOutcome) -> Style {
        switch outcome { case .exact, .reopened: return .exact; case .appOnly: return .approximate; case .notFound, .alreadyThere: return .none }
    }

    /// Seconds to fade in, to stay, and to fade out. With Reduce Motion it just appears and goes.
    public static func timeline(reduceMotion: Bool) -> (fadeIn: Double, hold: Double, fadeOut: Double) {
        reduceMotion ? (0, 1.2, 0) : (0.18, 0.9, 0.6)
    }

    /// How long to wait for the place to come forward before giving up on the ring.
    public static let waitSeconds = 1.5
    /// A short pause before looking, so the screen still showing the app you left is never ringed.
    static let firstLookSeconds = 0.15
    static func width(_ s: Style) -> CGFloat { s == .exact ? 3 : 2 }
    static func opacity(_ s: Style) -> Float { s == .exact ? 0.95 : (s == .beacon ? 0.5 : 0.6) }
}

final class LandingPanel: NSPanel {
    let ring = CALayer()
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .statusBar   // above the gray screen, like the banner
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true; isMovable = false; hidesOnDeactivate = false; canHide = false
        let v = NSView(); v.wantsLayer = true
        ring.cornerRadius = 12; ring.cornerCurve = .continuous
        ring.shadowRadius = 10; ring.shadowOpacity = 0.55; ring.shadowOffset = .zero
        v.layer!.addSublayer(ring)
        contentView = v
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(_ style: Landing.Style) {
        let color = NSColor(Tokens.accent).cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ring.frame = contentView?.bounds ?? .zero
        ring.borderColor = color; ring.borderWidth = Landing.width(style)
        ring.shadowColor = color; ring.opacity = Landing.opacity(style)
        CATransaction.commit()
    }
}

/// Watches `lastReturn` and rings the window that came forward.
@MainActor
public final class LandingController {
    private let c: SessionController
    private var panel: LandingPanel?
    private var running = false
    private var poll: Timer?
    private var hide: DispatchWorkItem?

    public init(controller: SessionController) { self.c = controller }
    public var isShowing: Bool { panel?.isVisible ?? false }
    var frameForTesting: NSRect? { panel?.frame }

    public func start() { guard !running else { return }; running = true; track() }
    public func stop() { running = false; cancel(); panel?.orderOut(nil) }

    private func track() {
        guard running else { return }
        withObservationTracking { _ = c.lastReturn } onChange: { [weak self] in
            Task { @MainActor in self?.returned(); self?.track() }
        }
    }

    private func cancel() { poll?.invalidate(); poll = nil; hide?.cancel(); hide = nil }

    func returned() {
        guard running, c.prefs.landingRing, c.isActive, !c.shadow, let r = c.lastReturn else { return }
        let style = Landing.style(for: r.outcome)
        guard style != .none else { return }
        cancel(); panel?.orderOut(nil)
        let want = r.place.window.app
        var waited = 0.0
        // Wait for the place to be in front, then ring the window that is. Activation takes a moment, and the window in front a moment
        // earlier is the one you just left.
        poll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                waited += 0.1
                if waited >= Landing.firstLookSeconds, (self.c.frontAppName?().map { $0 == want } ?? true), let f = self.frame() {
                    t.invalidate(); self.poll = nil
                    self.present(style, around: f)
                } else if waited >= Landing.waitSeconds {
                    t.invalidate(); self.poll = nil
                }
            }
        }
    }

    private func frame() -> NSRect? {
        guard let cg = c.frontWindowFrame?(), cg.width > 120, cg.height > 80, let primary = NSScreen.screens.first else { return nil }
        return CueLayout.cocoaRect(fromCG: cg, primaryHeight: primary.frame.height)
    }

    private func present(_ style: Landing.Style, around window: NSRect) {
        let p = panel ?? LandingPanel(); panel = p
        // A little outside the window, so the ring sits on its edge and not over its content.
        p.setFrame(window.insetBy(dx: -3, dy: -3), display: false)
        p.apply(style)
        let tl = Landing.timeline(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        p.alphaValue = tl.fadeIn == 0 ? 1 : 0
        p.orderFrontRegardless()
        if tl.fadeIn > 0 {
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = tl.fadeIn; ctx.timingFunction = CAMediaTimingFunction(name: .easeOut); p.animator().alphaValue = 1 }
        }
        let out = DispatchWorkItem { [weak p] in
            guard let p else { return }
            if tl.fadeOut == 0 { p.orderOut(nil); return }
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = tl.fadeOut; ctx.timingFunction = CAMediaTimingFunction(name: .easeIn); p.animator().alphaValue = 0 },
                                                 completionHandler: { p.orderOut(nil) })
        }
        hide = out
        DispatchQueue.main.asyncAfter(deadline: .now() + tl.fadeIn + tl.hold, execute: out)
    }
}

/// The beacon: while Hushd is nudging you, a faint ring outlines the window "Back to task" would take you to, even when something else is
/// on top of it, so the way back is something you can see and not something you have to remember. It asks for nothing, it is click-through,
/// and it is gone the moment you are back. Off by default. A steady ring with Reduce Motion on; otherwise it breathes slowly.
@MainActor
public final class BeaconController {
    private let c: SessionController
    private var panel: LandingPanel?
    private var timer: Timer?

    public init(controller: SessionController) { self.c = controller }
    public var isShowing: Bool { panel?.isVisible ?? false }
    var frameForTesting: NSRect? { panel?.frame }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
    }
    public func stop() { timer?.invalidate(); timer = nil; hide() }

    /// Looked at once a second, and only does anything while there is a real nudge and the switch is on.
    func update() {
        guard let place = c.beaconPlace, let cg = c.frameForPlace?(place.window), cg.width > 120, cg.height > 80,
              let primary = NSScreen.screens.first else { hide(); return }
        let rect = CueLayout.cocoaRect(fromCG: cg, primaryHeight: primary.frame.height)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) else { hide(); return }
        let p = panel ?? LandingPanel(); panel = p
        let target = rect.insetBy(dx: -3, dy: -3)
        let appeared = !p.isVisible
        if p.frame != target { p.setFrame(target, display: false) }
        if appeared {
            p.apply(.beacon)
            p.alphaValue = 1
            p.orderFrontRegardless()
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let breathe = CABasicAnimation(keyPath: "opacity")
                breathe.fromValue = 0.25; breathe.toValue = Landing.opacity(.beacon); breathe.duration = 2.4
                breathe.autoreverses = true; breathe.repeatCount = .infinity
                breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                p.ring.add(breathe, forKey: "breathe")
            }
        } else {
            p.apply(.beacon)   // follows the window if it moved
        }
    }

    private func hide() {
        panel?.ring.removeAllAnimations()
        panel?.orderOut(nil)
    }
}
