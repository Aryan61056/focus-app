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

    // Before explaining: the task, a way back, and a button that opens the explanation form at once. There is no wait and no hold.
    @ViewBuilder var waiting: some View {
        Text(CueCopy.shieldBody(shield.kind, tone: c.prefs.nudgeTone, task: c.taskName, longDetour: c.longDetour))
            .font(Tokens.text(14)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        if c.longDetour && shield.kind == .pause { Button(NudgeCopy.breakButton()) { c.takeNudgeBreak() }.buttonStyle(FocusButtonStyle(.primary, expand: true)) }
        Button("Back to task") { c.shieldBackToTask() }.buttonStyle(FocusButtonStyle(c.longDetour && shield.kind == .pause ? .secondary : .primary, expand: true))
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let lock = c.overrideLockRemaining
            VStack(alignment: .leading, spacing: 8) {
                if lock > 0 {
                    Text(CueCopy.lockedLine(Int(lock.rounded(.up)))).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                } else {
                    Button("Explain why this is on task") { c.openExplanation() }.buttonStyle(FocusButtonStyle(.secondary, expand: true))
                    Text(CueCopy.explainLine()).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
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
        Text("\(shield.attemptsLeft) \(shield.attemptsLeft == 1 ? "try" : "tries") left. A wrong answer costs something, and two lock explaining for \(Int(Shield.lockSeconds(after: c.overrideLocks) / 60)) minutes. An accepted explanation covers this page only, for \(Int(Shield.passSeconds(afterClaims: c.claimsAccepted) / 60)) minutes (explanation \(c.claimsAccepted + 1) of \(Shield.claimCap)).")
            .font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
    }

    func send() { c.submitExplanation(text) }
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
