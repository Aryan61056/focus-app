import AppKit
import SwiftUI
import Observation

// The shield: a panel on every display, above everything including the menu bar, the Dock and full-screen apps, that swallows the mouse
// and shows one card. It replaces the old pause screen that lived inside Focus's own window, which other windows simply covered.
// There is always a way out: "Back to task" never waits.

final class ShieldPanel: NSPanel {
    var onEscape: (() -> Void)?
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false; hidesOnDeactivate = false; ignoresMouseEvents = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

struct ShieldCard: View {
    @Bindable var c: SessionController
    var shield: Shield
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RingView(.drift, color: Tokens.ink).frame(width: 30, height: 30)
                Text(CueCopy.shieldTitle(shield.kind)).font(Tokens.rounded(24, .semibold))
            }
            if shield.asking { asking } else { waiting }
        }
        .padding(28).frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Tokens.window))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Tokens.line) }
        .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
        .foregroundStyle(Tokens.ink)
        .accessibilityElement(children: .contain)
    }
    static let width: CGFloat = 480

    // Before the wait is over: the task, a visible countdown, nothing else.
    @ViewBuilder var waiting: some View {
        Text(CueCopy.shieldBody(shield.kind, tone: c.prefs.nudgeTone, task: c.taskName, longDetour: c.longDetour))
            .font(Tokens.text(14)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        if c.longDetour && shield.kind == .pause { Button(NudgeCopy.breakButton()) { c.takeNudgeBreak() }.buttonStyle(FocusButtonStyle(.primary, expand: true)) }
        Button("Back to task") { c.shieldBackToTask() }.buttonStyle(FocusButtonStyle(c.longDetour && shield.kind == .pause ? .secondary : .primary, expand: true))
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let left = c.shieldWaitRemaining(), lock = c.overrideLockRemaining
            let total = max(1, shield.waitUntil - shield.since)
            VStack(alignment: .leading, spacing: 8) {
                if left > 0 {
                    ProgressBar(fraction: 1 - left / total)
                    Text(CueCopy.waitLine(Int(left.rounded(.up)))).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).monospacedDigit()
                } else if lock > 0 {
                    Text(CueCopy.lockedLine(Int(lock.rounded(.up)))).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                } else {
                    HoldPad(c: c).frame(height: 36)
                    Text(CueCopy.holdLine()).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // After: a short explanation, checked by Focus against the window.
    @ViewBuilder var asking: some View {
        Text(CueCopy.shieldAsk(task: c.taskName)).font(Tokens.text(15, .semibold))
        TextField(CueCopy.shieldPlaceholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain).lineLimit(3...5).focused($typing).onSubmit(send)
            .padding(12).frame(minHeight: 84, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusControl).fill(Tokens.control))
            .disabled(shield.checking)
            .onAppear { typing = true }
        if let m = shield.message {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(Tokens.ink2)
                Text(m).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink).fixedSize(horizontal: false, vertical: true)
            }.accessibilityElement(children: .combine)
        }
        Button("Back to task") { c.shieldBackToTask() }.buttonStyle(FocusButtonStyle(.primary, expand: true))
        HStack(spacing: 10) {
            Button("Check my answer", action: send).buttonStyle(FocusButtonStyle(.secondary, expand: true))
                .disabled(shield.checking || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if shield.checking { ProgressView().controlSize(.small); Text("Reading the window").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
        }
        Text("\(shield.attemptsLeft) \(shield.attemptsLeft == 1 ? "try" : "tries") left. Two wrong answers lock this for \(Int(Shield.lockSeconds / 60)) minutes.")
            .font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
    }

    func send() { c.submitExplanation(text) }
}

/// Press and hold to open the explanation form. Native AppKit, not a SwiftUI gesture: mouse down and up reach it directly, even when
/// Focus is not the active app, and a test can drive it. The fill shows the hold; letting go starts over.
struct HoldPad: NSViewRepresentable {
    var c: SessionController
    func makeNSView(context: Context) -> HoldPadView { HoldPadView(c: c) }
    func updateNSView(_ v: HoldPadView, context: Context) { v.c = c }
}

final class HoldPadView: NSView {
    var c: SessionController
    private var timer: Timer?
    private(set) var pressed = false
    init(c: SessionController) {
        self.c = c
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 36))
        wantsLayer = true
        setAccessibilityRole(.button)
        setAccessibilityLabel("Hold to explain")
        setAccessibilityHelp("Takes \(Int(Shield.holdSeconds)) seconds of holding. With VoiceOver, activating it starts the hold for you.")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) { press() }
    override func mouseUp(with event: NSEvent) { release() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { release() } }

    /// VoiceOver cannot hold a mouse button, so activating the button starts the same hold and it runs its course.
    override func accessibilityPerformPress() -> Bool { c.beginShieldHold(); startRedraw(); return true }

    func press() { pressed = true; c.beginShieldHold(); startRedraw(); needsDisplay = true }
    func release() { pressed = false; c.endShieldHold(); stopRedrawIfIdle(); needsDisplay = true }

    private func startRedraw() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; self.c.updateShieldHold(); self.needsDisplay = true; self.stopRedrawIfIdle() }
        }
    }
    private func stopRedrawIfIdle() { if c.shieldHoldStart == nil { timer?.invalidate(); timer = nil } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds, radius = Tokens.radiusControl
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let ink = dark ? NSColor(srgbRed: 0.93, green: 0.95, blue: 0.94, alpha: 1) : NSColor(srgbRed: 0.09, green: 0.11, blue: 0.09, alpha: 1)
        let track = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        ink.withAlphaComponent(0.1).setFill(); track.fill()
        let p = CGFloat(c.shieldHoldProgress())
        if p > 0 {
            NSGraphicsContext.saveGraphicsState(); track.addClip()
            (dark ? NSColor(srgbRed: 0.47, green: 0.84, blue: 0.62, alpha: 0.55) : NSColor(srgbRed: 0.106, green: 0.459, blue: 0.282, alpha: 0.28)).setFill()
            NSRect(x: 0, y: 0, width: r.width * p, height: r.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        ink.withAlphaComponent(0.14).setStroke(); track.lineWidth = 1; track.stroke()
        let label = (p > 0 ? "Keep holding" : "Hold to explain") as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: ink]
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
    }
}

struct ProgressBar: View {
    var fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.track)
                Capsule().fill(Tokens.accent).frame(width: max(6, g.size.width * min(1, max(0, fraction))))
            }
        }.frame(height: 6).accessibilityHidden(true)
    }
}

struct ShieldContent: View {
    @Bindable var c: SessionController
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            if let s = c.shield { ShieldCard(c: c, shield: s) }
        }
    }
}

/// Keeps one shield panel on every display while `SessionController.shield` is set. Brings Focus forward so the keyboard works,
/// follows display changes, and never closes by itself: only the controller clearing the shield does.
@MainActor
public final class ShieldController {
    private let c: SessionController
    private var panels: [CGDirectDisplayID: ShieldPanel] = [:]
    private var timer: Timer?
    private var running = false
    private var shown = false

    public init(controller: SessionController) { self.c = controller }
    public var isShowing: Bool { panels.values.contains { $0.isVisible } }
    var panelsForTesting: [ShieldPanel] { Array(panels.values) }

    public func start() { guard !running else { return }; running = true; track() }
    public func stop() { running = false; hide() }

    private func track() {
        guard running else { return }
        withObservationTracking { _ = c.shield?.kind } onChange: { [weak self] in
            Task { @MainActor in self?.refresh(); self?.track() }
        }
        refresh()
    }

    private static func id(_ s: NSScreen) -> CGDirectDisplayID { (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }

    func refresh() {
        guard running, c.shield != nil else { hide(); return }
        let screens = NSScreen.screens
        var live = Set<CGDirectDisplayID>()
        for s in screens {
            let key = Self.id(s); live.insert(key)
            let p = panels[key] ?? makePanel(); panels[key] = p
            if p.frame != s.frame { p.setFrame(s.frame, display: true) }
            p.orderFrontRegardless()
        }
        for (key, p) in panels where !live.contains(key) { p.orderOut(nil); panels[key] = nil }
        if !shown {
            shown = true
            NSApp.activate(ignoringOtherApps: true)
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.keepOnTop() } }
        }
        keepOnTop()
    }

    /// Display changes and other apps raising themselves must not uncover the screen; the card's display takes the keyboard.
    private func keepOnTop() {
        guard c.shield != nil else { return }
        let here = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        for s in NSScreen.screens {
            guard let p = panels[Self.id(s)] else { continue }
            if p.frame != s.frame { p.setFrame(s.frame, display: true) }
            if !p.isVisible { p.orderFrontRegardless() }
            if s == here, !p.isKeyWindow, NSApp.isActive { p.makeKey() }
        }
    }

    private func makePanel() -> ShieldPanel {
        let p = ShieldPanel()
        p.onEscape = { [weak self] in self?.c.shieldBackToTask() }
        let blur = NSVisualEffectView(); blur.material = .fullScreenUI; blur.blendingMode = .behindWindow; blur.state = .active
        let host = NSHostingView(rootView: ShieldContent(c: c))
        host.sizingOptions = []; host.safeAreaRegions = []
        host.frame = blur.bounds; host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
        p.contentView = blur
        return p
    }

    private func hide() {
        timer?.invalidate(); timer = nil; shown = false
        panels.values.forEach { $0.orderOut(nil) }
    }
}
