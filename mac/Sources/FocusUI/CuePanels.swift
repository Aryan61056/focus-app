import AppKit
import SwiftUI
import Observation

// The small banner that sits over the window you are in (heads-up and reminder). Like the notch panel it is borderless, never takes focus
// from the app you are in, and exists only while a session runs. The screen-covering shield lives in ShieldPanel.swift.

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
            Text(banner.kind == .reminder && c.closeIsNext ? CueCopy.closeWarning : CueCopy.bannerTitle(banner.kind, tone: c.prefs.nudgeTone, task: c.taskName))
                .font(Tokens.text(13.5, .semibold)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if banner.kind == .early {
                Button("This is part of it") { c.bannerPartOfIt() }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
            Button { c.bannerBackToTask() } label: {
                Text("Back to task").font(Tokens.text(12.5, .semibold)).foregroundStyle(Color(red: 0.02, green: 0.1, blue: 0.05))
                    .padding(.horizontal, 14).frame(height: 28)
            }
            // The banner never takes focus, and glass in a window that is not key draws grey, so its one way forward is a solid pill.
            .buttonStyle(PillStyle())
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

/// The new surfaces as plain views, for the snapshot tool that renders the app offscreen. Nothing here reads the screen.
public enum CuePreview {
    @MainActor public static func banner(_ c: SessionController, _ kind: Banner.Kind) -> some View { BannerView(c: c, banner: Banner(kind: kind, at: 0)) }
    @MainActor public static func shield(_ c: SessionController) -> some View { ShieldContent(c: c) }
    @MainActor public static func rhythm(_ c: SessionController) -> some View { RhythmCard(c: c).padding(CueLayout.margin) }
}
