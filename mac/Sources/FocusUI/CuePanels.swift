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
        // Hiding Focus (Command-H, or Hide Others from another app) hides its main window, never a nudge.
        canHide = false
    }
    override var canBecomeKey: Bool { false }
}

struct BannerView: View {
    @Bindable var c: SessionController
    var banner: Banner
    @State private var closeHover = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            mark.frame(width: 28, height: 28).padding(.top, 1)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Tokens.fixed(.headline, .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, dismissible ? 22 : 0)
                    meta
                }
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 16).padding(.trailing, 14).padding(.top, 14).padding(.bottom, 14)
        .frame(width: Self.width, alignment: .leading)
        .overlay(alignment: .topTrailing) { if dismissible { close.padding(8) } }
        .cueSurface()
        .foregroundStyle(Tokens.ink)
        .padding(CueLayout.margin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    static let width: CGFloat = 440

    var rhythm: RhythmPrompt.Kind? { c.rhythmPrompt?.kind }
    var title: String { CueCopy.bannerTitle(banner.kind, tone: c.prefs.nudgeTone, task: c.taskName, rhythm: rhythm) }
    /// The heads-up, the reminder and the check-in can be put away; a scheduled prompt is answered with one of its two buttons.
    var dismissible: Bool { banner.kind != .rhythm }

    /// State by shape first: a dashed ring for a hunch, the gapped ring for a slip (amber, the one color for it), a ring with a dot for a break.
    @ViewBuilder var mark: some View {
        switch banner.kind {
        case .early: RingView(.unsure, color: Tokens.ink2)
        case .reminder, .checkIn: RingView(.drift, color: Tokens.slip)
        case .rhythm: RingView(rhythm?.ring ?? .on, color: Tokens.accent)
        }
    }

    /// One line of what Focus saw, with the sparkle wherever the AI did the work. Numbers are monospaced so they never jitter.
    @ViewBuilder var meta: some View {
        HStack(spacing: 6) {
            switch banner.kind {
            case .early:
                let n = c.headsUpCounts
                sparkle
                Text(CueCopy.headsUpMeta(away: n.away, of: n.total)).monospacedDigit()
            case .reminder where c.closeIsNext:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(Tokens.slip)
                Text(CueCopy.closeWarning).foregroundStyle(Tokens.ink)
            case .reminder:
                sparkle
                Text(CueCopy.reminderMeta)
                TimelineView(.everySecond) { _ in Text(Self.clock(c.offTopicSecondsNow())).monospacedDigit().foregroundStyle(Tokens.slipInk) }
            case .checkIn:
                sparkle
                Text(CueCopy.checkInMeta)
            case .rhythm:
                Image(systemName: "clock").font(.system(size: 10, weight: .semibold))
                Text(CueCopy.rhythmMeta(rhythm ?? .checkIn, checkInMinutes: c.prefs.checkInMinutes))
            }
            Spacer(minLength: 8)
            if banner.kind == .reminder || banner.kind == .checkIn, c.prefs.escalate, EscalationPlan.of(c.sessionPreset) != nil { LadderDots(step: c.escalationStep) }
        }
        .font(Tokens.fixed(.caption, .medium)).foregroundStyle(Tokens.ink2).lineLimit(1)
    }

    var sparkle: some View { Image(systemName: "sparkle").font(.system(size: 10, weight: .semibold)).foregroundStyle(Tokens.accent).accessibilityHidden(true) }

    /// Two answers at most: the way back (or, for a schedule, the plan) is primary; the other is quiet.
    @ViewBuilder var actions: some View {
        HStack(spacing: 8) {
            switch banner.kind {
            case .early, .reminder:
                Button("Back to task") { c.bannerBackToTask() }.buttonStyle(FocusButtonStyle(.primary, small: true))
                Button("This is part of it") { c.bannerPartOfIt() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
            case .checkIn:
                Button("Back to task") { c.answerCheckIn(onTask: false) }.buttonStyle(FocusButtonStyle(.primary, small: true))
                Button("Yes, this is part of it") { c.answerCheckIn(onTask: true) }.buttonStyle(FocusButtonStyle(.secondary, small: true))
            case .rhythm:
                if case .breakDue(let m)? = rhythm {
                    Button("Start the break") { c.rhythmTakeBreak() }.buttonStyle(FocusButtonStyle(.primary, small: true))
                        .accessibilityLabel("Start the \(m) minute break")
                    Button("Five more minutes") { c.rhythmKeepGoing() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                } else {
                    Button("Yes, keep going") { c.rhythmKeepGoing() }.buttonStyle(FocusButtonStyle(.primary, small: true))
                    Button("Take a \(c.rhythmBreakMinutes) minute break") { c.rhythmTakeBreak() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                }
            }
        }
    }

    var close: some View {
        Button { c.dismissBanner() } label: {
            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(closeHover ? Tokens.ink : Tokens.ink2)
                .frame(width: 22, height: 22).background(Circle().fill(closeHover ? Tokens.controlHover : Tokens.control))
                .frame(width: Tokens.minHit, height: Tokens.minHit).contentShape(Circle())
        }
        .buttonStyle(.plain).onHover { closeHover = $0 }.animation(Motion.hover, value: closeHover)
        .help("Hide until you drift again")
        .accessibilityLabel(banner.kind == .early ? "Hide this heads-up" : "Hide this reminder")
    }

    static func clock(_ s: Double) -> String { let v = max(0, Int(s)); return "\(v / 60):" + String(format: "%02d", v % 60) }
}

/// How far the ladder has climbed: one dot per step, amber up to where it is. Says it in words to VoiceOver and on hover.
struct LadderDots: View {
    var step: EscalationStep
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<CueCopy.ladderSteps.count, id: \.self) { i in
                Capsule().fill(i <= step.rawValue ? Tokens.slip : Tokens.track).frame(width: i == step.rawValue ? 12 : 6, height: 6)
            }
        }
        .help(CueCopy.ladderLabel(step))
        .accessibilityElement().accessibilityLabel(CueCopy.ladderLabel(step))
    }
}

/// Keeps the banner over the window you are in. It drops in a few points and fades, follows the window if it moves, and never takes focus.
@MainActor
public final class BannerController {
    private let c: SessionController
    private var panel: BannerPanel?
    private var host: NSHostingView<BannerView>?
    private var follow: Timer?
    private var running = false
    private var shownKind: Banner.Kind?
    private var size = CGSize.zero

    public init(controller: SessionController) { self.c = controller }
    public var isShowing: Bool { panel?.isVisible ?? false }
    var frameForTesting: NSRect? { panel?.frame }
    var sizeForTesting: CGSize { size }

    public func start() { guard !running else { return }; running = true; track() }
    public func stop() { running = false; follow?.invalidate(); follow = nil; panel?.orderOut(nil) }

    private func track() {
        guard running else { return }
        withObservationTracking { _ = c.banner; _ = c.prefs.nudgeTone; _ = c.taskName; _ = c.rhythmPrompt; _ = c.escalationStep } onChange: { [weak self] in
            Task { @MainActor in self?.refresh(); self?.track() }
        }
        refresh()
    }

    func refresh() {
        guard running, let b = c.banner else { hide(); return }
        let p = panel ?? BannerPanel(); panel = p
        let view = BannerView(c: c, banner: b)
        if let host { host.rootView = view } else {
            let h = NSHostingView(rootView: view)
            h.sizingOptions = []; h.safeAreaRegions = []
            p.contentView = h; host = h
        }
        // The height follows the title (one or two lines). The panel's own hosting view does not size itself (sizingOptions is empty,
        // so its fittingSize is not the content's), so a throwaway controller measures the view, outside any layout pass.
        let fit = NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: BannerView.width + 2 * CueLayout.margin, height: 1000))
        size = CGSize(width: BannerView.width + 2 * CueLayout.margin, height: max(fit.height, 80))
        let arriving = !p.isVisible || shownKind == nil
        shownKind = b.kind
        let target = frame()
        if arriving, let target {
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            p.setFrame(reduce ? target : target.offsetBy(dx: 0, dy: 10), display: true)
            p.alphaValue = 0; p.orderFrontRegardless()
            animate(p, frame: target, alpha: 1, duration: 0.32)
        } else if let target, p.frame != target {
            animate(p, frame: target, alpha: 1, duration: 0.2)
        }
        if follow == nil { follow = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.reposition() } } }
    }

    private func reposition() { if let p = panel, p.isVisible, let f = frame(), p.frame != f { p.setFrame(f, display: true) } }

    private func frame() -> NSRect? {
        let window = windowRectInCocoa(c)
        let here = window.flatMap { w in NSScreen.screens.first { $0.frame.intersects(w) && NSMouseInRect(NSPoint(x: w.midX, y: w.midY), $0.frame, false) } } ?? screen(containing: NSEvent.mouseLocation)
        guard let s = here else { return nil }
        return CueLayout.bannerFrame(content: CGSize(width: size.width - 2 * CueLayout.margin, height: size.height - 2 * CueLayout.margin), window: window, screen: s.frame, visible: s.visibleFrame)
    }

    private func hide() {
        follow?.invalidate(); follow = nil; shownKind = nil
        guard let p = panel, p.isVisible else { return }
        animate(p, frame: p.frame, alpha: 0, duration: 0.18) { [weak self] in if self?.c.banner == nil { p.orderOut(nil) } }
    }

    private func animate(_ p: NSPanel, frame: NSRect, alpha: CGFloat, duration: Double, done: (() -> Void)? = nil) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.15; p.animator().alphaValue = alpha; p.animator().setFrame(frame, display: true) }, completionHandler: done)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration; ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            p.animator().alphaValue = alpha; p.animator().setFrame(frame, display: true)
        }, completionHandler: done)
    }
}

/// The new surfaces as plain views, for the snapshot tool that renders the app offscreen. Nothing here reads the screen.
public enum CuePreview {
    @MainActor public static func banner(_ c: SessionController, _ kind: Banner.Kind) -> some View { BannerView(c: c, banner: Banner(kind: kind, at: 0)) }
    @MainActor public static func shield(_ c: SessionController) -> some View { ShieldContent(c: c) }
    @MainActor public static func rhythm(_ c: SessionController) -> some View { RhythmCard(c: c).padding(CueLayout.margin) }
    @MainActor public static func nudge(_ c: SessionController) -> some View { NudgeCard(c: c, kind: c.surface?.kind ?? "card") }
    @MainActor public static func checkIn(_ c: SessionController) -> some View { CheckInCard(c: c) }
}
