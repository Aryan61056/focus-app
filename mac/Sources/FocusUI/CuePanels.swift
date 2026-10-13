import AppKit
import SwiftUI
import Observation

// The panels that sit over other apps: the small banner (heads-up and reminder) and the friction panel (a moment before a site opens again).
// Like the notch panel, they are borderless, never take focus from the app you are in, and exist only while a session runs.

/// Where the panels go. Pure, so the arithmetic is tested; the controllers only apply it.
public enum CueLayout {
    /// Room around a panel's content for its shadow.
    static let margin: CGFloat = 18

    /// The window's frame from Core Graphics (top left origin, measured on the primary display) in Cocoa screen coordinates (bottom left origin).
    static func cocoaRect(fromCG cg: CGRect, primaryHeight: CGFloat) -> NSRect {
        NSRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
    }

    /// The banner sits centred near the top of the window, below its title bar. With no window it sits under the menu bar of `screen`.
    static func bannerFrame(content: CGSize, window: NSRect?, screen: NSRect, visible: NSRect) -> NSRect {
        let size = CGSize(width: content.width + 2 * margin, height: content.height + 2 * margin)
        var top: CGFloat, midX: CGFloat
        if let w = window, w.width > 120, w.height > 80 {
            top = w.maxY - 38; midX = w.midX
        } else {
            top = visible.maxY - 10; midX = screen.midX
        }
        top += margin
        var f = NSRect(x: midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        // Keep it on the display it is on.
        f.origin.x = min(max(f.origin.x, screen.minX + 8 - margin), screen.maxX - f.width - 8 + margin)
        f.origin.y = min(max(f.origin.y, screen.minY), screen.maxY - f.height)
        return f
    }

    /// The friction panel covers the window it is about, so nothing in it can be used until you answer. With no window it is a card in the middle of the screen.
    static func frictionFrame(card: CGSize, window: NSRect?, screen: NSRect) -> (frame: NSRect, covers: Bool) {
        if let w = window, w.width >= card.width + 40, w.height >= card.height + 40 { return (w, true) }
        let size = CGSize(width: card.width + 2 * margin, height: card.height + 2 * margin)
        return (NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2 + 40, width: size.width, height: size.height), false)
    }
}

private func screen(containing p: NSPoint) -> NSScreen? { NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first }

@MainActor private func windowRectInCocoa(_ c: SessionController) -> NSRect? {
    guard let cg = c.frontWindowFrame?(), let primary = NSScreen.screens.first else { return nil }
    return CueLayout.cocoaRect(fromCG: cg, primaryHeight: primary.frame.height)
}

// MARK: banner

final class BannerPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        // Level of the notch panel: above the gray screen, so it stays readable and in color while everything else drains.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false; hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { false }
}

struct BannerView: View {
    @Bindable var c: SessionController
    var banner: Banner
    var body: some View {
        HStack(spacing: 12) {
            RingView(banner.kind == .early ? .unsure : .drift, color: Tokens.ink).frame(width: 20, height: 20)
            Text(CueCopy.bannerTitle(banner.kind, tone: c.prefs.nudgeTone, task: c.taskName))
                .font(Tokens.text(13.5, .semibold)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if banner.kind == .early {
                Button("This is part of it") { c.bannerPartOfIt() }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
            Button("Back to task") { c.bannerBackToTask() }.buttonStyle(FocusButtonStyle(.primary, small: true))
            Button { c.dismissBanner() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Tokens.ink2).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(banner.kind == .early ? "Hide this heads-up" : "Hide this reminder")
        }
        .padding(.leading, 14).padding(.trailing, 8).frame(width: Self.width(banner.kind), height: Self.height)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Tokens.line) }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .foregroundStyle(Tokens.ink)
        .padding(CueLayout.margin)
        .accessibilityElement(children: .contain)
    }
    static let height: CGFloat = 46
    static func width(_ k: Banner.Kind) -> CGFloat { k == .early ? 520 : 400 }
    static func contentSize(_ k: Banner.Kind) -> CGSize { CGSize(width: width(k), height: height) }
}

/// Keeps the banner over the window you are in. It fades in and out, follows the window if it moves, and never takes focus.
@MainActor
public final class BannerController {
    private let c: SessionController
    private var panel: BannerPanel?
    private var follow: Timer?
    private var running = false
    private var shownKind: Banner.Kind?

    public init(controller: SessionController) { self.c = controller }
    public var isShowing: Bool { panel?.isVisible ?? false }
    var frameForTesting: NSRect? { panel?.frame }

    public func start() { guard !running else { return }; running = true; track() }
    public func stop() { running = false; follow?.invalidate(); follow = nil; panel?.orderOut(nil) }

    private func track() {
        guard running else { return }
        withObservationTracking { _ = c.banner; _ = c.prefs.nudgeTone; _ = c.taskName } onChange: { [weak self] in
            Task { @MainActor in self?.refresh(); self?.track() }
        }
        refresh()
    }

    func refresh() {
        guard running, let b = c.banner else { hide(); return }
        let p = panel ?? BannerPanel(); panel = p
        if shownKind != b.kind || p.contentView == nil {
            let host = NSHostingView(rootView: BannerView(c: c, banner: b))
            host.sizingOptions = []; host.safeAreaRegions = []
            p.contentView = host
            shownKind = b.kind
        } else if let host = p.contentView as? NSHostingView<BannerView> { host.rootView = BannerView(c: c, banner: b) }
        place(p, b.kind)
        if !p.isVisible {
            p.alphaValue = 0; p.orderFrontRegardless()
            fade(p, to: 1)
        }
        if follow == nil { follow = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { if let k = self?.shownKind, let p = self?.panel { self?.place(p, k) } } } }
    }

    private func place(_ p: NSPanel, _ k: Banner.Kind) {
        let window = windowRectInCocoa(c)
        let here = window.flatMap { w in NSScreen.screens.first { $0.frame.intersects(w) && NSMouseInRect(NSPoint(x: w.midX, y: w.midY), $0.frame, false) } } ?? screen(containing: NSEvent.mouseLocation)
        guard let s = here else { return }
        let f = CueLayout.bannerFrame(content: BannerView.contentSize(k), window: window, screen: s.frame, visible: s.visibleFrame)
        if p.frame != f { p.setFrame(f, display: true) }
    }

    private func hide() {
        follow?.invalidate(); follow = nil; shownKind = nil
        guard let p = panel, p.isVisible else { return }
        fade(p, to: 0) { [weak self] in if self?.c.banner == nil { p.orderOut(nil) } }
    }

    private func fade(_ p: NSPanel, to alpha: CGFloat, done: (() -> Void)? = nil) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { p.alphaValue = alpha; done?(); return }
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.2; ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1); p.animator().alphaValue = alpha }, completionHandler: done)
    }
}

// MARK: friction

final class FrictionPanel: NSPanel {
    var onEscape: (() -> Void)?
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false; hidesOnDeactivate = false
    }
    // The reason field needs the keyboard, so this panel can be key even though it never makes Focus the active app.
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Press and hold for a few seconds. The fill shows how far along it is; letting go starts over. The controller finishes the hold.
struct HoldButton: View {
    @Bindable var c: SessionController
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: c.frictionHoldStart == nil)) { _ in
            let p = c.frictionHoldProgress()
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Tokens.radiusControl).fill(Tokens.control)
                GeometryReader { g in RoundedRectangle(cornerRadius: Tokens.radiusControl).fill(Tokens.accentSoft).frame(width: g.size.width * p) }
                Text(p > 0 ? "Keep holding" : "Hold to open it anyway").font(Tokens.text(13, .semibold)).frame(maxWidth: .infinity)
            }
            .frame(height: 34)
            .overlay { RoundedRectangle(cornerRadius: Tokens.radiusControl).strokeBorder(Tokens.line) }
            .contentShape(RoundedRectangle(cornerRadius: Tokens.radiusControl))
        }
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in c.beginFrictionHold() }.onEnded { _ in c.endFrictionHold() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold to open it anyway")
        .accessibilityHint("Takes \(Int(Friction.holdSeconds)) seconds. You can also type a reason instead.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { c.beginFrictionHold() }
    }
}

struct FrictionCard: View {
    @Bindable var c: SessionController
    @State private var reason = ""
    @FocusState private var typing: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RingView(.drift, color: Tokens.ink).frame(width: 22, height: 22)
                Text(CueCopy.frictionTitle(task: c.taskName)).font(Tokens.rounded(17, .semibold))
            }
            Text(CueCopy.frictionBody(task: c.taskName)).font(Tokens.text(13)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            Button("Back to task") { c.frictionBackToTask() }.buttonStyle(FocusButtonStyle(.primary, expand: true))
            HoldButton(c: c)
            HStack(spacing: 8) {
                TextField("Or say how this helps", text: $reason).textFieldStyle(.plain).focused($typing).onSubmit(submit)
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: Tokens.radiusControl).fill(Tokens.control))
                Button("Open it", action: submit).buttonStyle(FocusButtonStyle(.secondary)).disabled(!Friction.acceptable(reason: reason))
            }
            Text("A reason counts as \u{201C}That was fine\u{201D} for this window. The words are not kept.").font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
        }
        .padding(20).frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Tokens.line) }
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
        .foregroundStyle(Tokens.ink)
        .accessibilityElement(children: .contain)
    }
    func submit() { if c.submitFrictionReason(reason) { reason = "" } }
    static let width: CGFloat = 380
    static let height: CGFloat = 300
}

struct FrictionContent: View {
    @Bindable var c: SessionController
    var covers: Bool
    var body: some View {
        ZStack {
            if covers { Color.black.opacity(0.34) }
            FrictionCard(c: c).padding(covers ? 0 : CueLayout.margin)
        }
    }
}

/// Covers the window you reopened with a card that asks for a short hold or a reason. It sits only over that window; the rest of the screen is untouched.
@MainActor
public final class FrictionController {
    private let c: SessionController
    private var panel: FrictionPanel?
    private var timer: Timer?
    private var running = false
    private var covers = false

    public init(controller: SessionController) { self.c = controller }
    public var isShowing: Bool { panel?.isVisible ?? false }

    public func start() { guard !running else { return }; running = true; track() }
    public func stop() { running = false; timer?.invalidate(); timer = nil; panel?.orderOut(nil) }

    private func track() {
        guard running else { return }
        withObservationTracking { _ = c.friction } onChange: { [weak self] in
            Task { @MainActor in self?.refresh(); self?.track() }
        }
        refresh()
    }

    func refresh() {
        guard running, c.friction != nil else { timer?.invalidate(); timer = nil; panel?.orderOut(nil); return }
        let p = panel ?? FrictionPanel(); panel = p
        p.onEscape = { [weak self] in self?.c.frictionBackToTask() }
        place(p)
        if !p.isVisible { p.makeKeyAndOrderFront(nil) }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { guard let self else { return }; self.c.updateFrictionHold(); if let p = self.panel, p.isVisible { self.place(p) } }
            }
        }
    }

    private func place(_ p: FrictionPanel) {
        let window = windowRectInCocoa(c)
        guard let s = window.flatMap({ w in NSScreen.screens.first { NSMouseInRect(NSPoint(x: w.midX, y: w.midY), $0.frame, false) } }) ?? screen(containing: NSEvent.mouseLocation) else { return }
        let (f, covers) = CueLayout.frictionFrame(card: CGSize(width: FrictionCard.width, height: FrictionCard.height), window: window, screen: s.frame)
        if p.contentView == nil || self.covers != covers {
            let host = NSHostingView(rootView: FrictionContent(c: c, covers: covers))
            host.sizingOptions = []; host.safeAreaRegions = []
            p.contentView = host; self.covers = covers
        }
        if p.frame != f { p.setFrame(f, display: true) }
    }
}

/// The new surfaces as plain views, for the snapshot tool that renders the app offscreen. Nothing here reads the screen.
public enum CuePreview {
    @MainActor public static func banner(_ c: SessionController, _ kind: Banner.Kind) -> some View { BannerView(c: c, banner: Banner(kind: kind, at: 0)) }
    @MainActor public static func friction(_ c: SessionController) -> some View { FrictionContent(c: c, covers: false) }
    @MainActor public static func rhythm(_ c: SessionController) -> some View { RhythmCard(c: c).padding(CueLayout.margin) }
}
