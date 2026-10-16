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

/// The shield's one column, centred on a dimmed, blurred screen. Always dark, whatever the system appearance, because it sits on a dark
/// veil: the ring with the time away, one title, one sentence, the way back as the big button, and explaining as the quiet second path.
struct ShieldCard: View {
    @Bindable var c: SessionController
    var shield: Shield
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ShieldRing(c: c).frame(width: 104, height: 104).padding(.bottom, Space.l)
            Text(CueCopy.shieldTitle(shield.kind)).font(Tokens.rounded(.title2, .semibold)).multilineTextAlignment(.center)
            Text(shield.asking ? CueCopy.shieldAsk(task: c.taskName) : CueCopy.shieldBody(shield.kind, tone: c.prefs.nudgeTone, task: c.taskName, longDetour: c.longDetour))
                .font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.top, Space.xs)
            Group { if shield.asking { asking } else { waiting } }.padding(.top, Space.xl)
        }
        .frame(width: Self.width)
        .foregroundStyle(Tokens.ink)
        .accessibilityElement(children: .contain)
    }
    static let width: CGFloat = 400

    // Before explaining: the way back, and explaining one press away. No wait and no hold, unless holding was switched on.
    @ViewBuilder var waiting: some View {
        VStack(spacing: Space.s) {
            if c.longDetour && shield.kind == .pause {
                Button(NudgeCopy.breakButton()) { c.takeNudgeBreak() }.buttonStyle(ShieldButtonStyle(.primary))
            }
            backToTask(primary: !(c.longDetour && shield.kind == .pause))
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let lock = c.overrideLockRemaining
                if lock > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(Tokens.symbol(11, .semibold))
                        Text("Explaining opens in")
                        Text(BannerView.clock(lock.rounded(.up))).monospacedDigit().foregroundStyle(Tokens.ink)
                    }
                    .font(Tokens.text(.caption, .medium)).foregroundStyle(Tokens.ink2).frame(height: 36)
                    .accessibilityElement(children: .combine)
                } else {
                    VStack(spacing: Space.xxs) {
                        Button { c.openExplanation() } label: { Label("Explain why this is on task", systemImage: "sparkle") }.buttonStyle(ShieldButtonStyle(.quiet))
                        Text("Focus checks your words against the window").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                    }
                }
            }
            if let m = shield.message, c.overrideLockRemaining <= 0 { ShieldNotice(text: m).padding(.top, Space.xs) }
        }
    }

    // Explaining: one field, the two ways forward, and the rules as three short facts.
    @ViewBuilder var asking: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ZStack(alignment: .bottomTrailing) {
                TextField(CueCopy.shieldPlaceholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain).font(Tokens.text(.body)).lineLimit(3...5).focused($typing).onSubmit(send)
                    .padding(.horizontal, Space.s).padding(.top, Space.s).padding(.bottom, 26)
                    .frame(minHeight: 96, alignment: .topLeading)
                    .disabled(shield.checking)
                    .onAppear { typing = true }
                let words = OverrideClaim.tokens(text).count
                Text("\(min(words, OverrideClaim.minWords))/\(OverrideClaim.minWords) words").font(Tokens.text(.caption2, .medium)).monospacedDigit()
                    .foregroundStyle(words >= OverrideClaim.minWords ? Tokens.accent : Tokens.ink2).padding(Space.xs)
                    .accessibilityLabel("\(words) words, at least \(OverrideClaim.minWords)")
            }
            .background(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay { RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).strokeBorder(typing ? Tokens.accent.opacity(0.7) : Color.white.opacity(0.14)) }
            if let m = shield.message { ShieldNotice(text: m) }
            HStack(spacing: Space.xs) {
                Button(action: send) {
                    HStack(spacing: 6) {
                        if shield.checking { ProgressView().controlSize(.small).tint(Tokens.ink); Text("Reading the window") }
                        else { Image(systemName: "sparkle"); Text("Check my answer") }
                    }
                }
                .buttonStyle(ShieldButtonStyle(.secondary))
                .disabled(shield.checking || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                backToTask(primary: true)
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                ShieldChip(symbol: "arrow.counterclockwise", text: "\(shield.attemptsLeft) \(shield.attemptsLeft == 1 ? "try" : "tries") left")
                ShieldChip(symbol: "clock", text: "Pass lasts \(Int(Shield.passSeconds(afterClaims: c.claimsAccepted) / 60)) min")
                ShieldChip(symbol: "number", text: "\(min(c.claimsAccepted + 1, Shield.claimCap)) of \(Shield.claimCap) this session")
                Spacer(minLength: 0)
            }
            .help("A wrong answer is acted on at once, and two lock explaining for \(Int(Shield.lockSeconds(after: c.overrideLocks) / 60)) minutes. An accepted explanation covers this page only.")
        }
    }

    func send() { c.submitExplanation(text) }

    /// Back to task: one press (Return or Escape too), or, if holding was switched on in Settings, a three second press. Never behind a lock.
    @ViewBuilder func backToTask(primary: Bool) -> some View {
        if c.prefs.holdToReturn {
            VStack(spacing: Space.xxs) {
                HoldPad(c: c).frame(height: 44)
                Text(CueCopy.backHoldLine()).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
            }
        } else if shield.asking {
            Button("Back to task") { c.shieldBackToTask() }.buttonStyle(ShieldButtonStyle(primary ? .primary : .secondary))
        } else {
            Button("Back to task") { c.shieldBackToTask() }.buttonStyle(ShieldButtonStyle(primary ? .primary : .secondary)).keyboardShortcut(.defaultAction)
        }
    }
}

/// The ring over the shield: the slip's gapped ring, drawn large and thin, with the time away inside it.
struct ShieldRing: View {
    var c: SessionController
    var body: some View {
        ZStack {
            Circle().fill(Tokens.slip.opacity(0.1))
            Circle().stroke(Tokens.track, lineWidth: 4).padding(10)
            Circle().trim(from: 0, to: 281.5 / 360).rotation(.degrees(-60))
                .stroke(Tokens.slip, style: StrokeStyle(lineWidth: 4, lineCap: .round)).padding(10)
            TimelineView(.everySecond) { _ in
                let s = c.offTopicSecondsNow()
                VStack(spacing: 0) {
                    if s >= 1 {
                        Text(BannerView.clock(s)).font(Tokens.rounded(.title3, .semibold)).monospacedDigit()
                        Text("away").font(Tokens.text(.caption2, .medium)).foregroundStyle(Tokens.ink2)
                    } else {
                        Image(systemName: "sparkle").font(Tokens.symbol(22, .semibold)).foregroundStyle(Tokens.slip)
                    }
                }
            }
        }
        .accessibilityElement().accessibilityLabel("Time away from the task, \(Int(c.offTopicSecondsNow() / 60)) minutes")
    }
}

/// The shield's buttons: big capsules that read on the dark veil whatever window state (never glass, which grays in an inactive panel).
struct ShieldButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind
    init(_ kind: Kind) { self.kind = kind }
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration, kind: kind) }
    struct Inner: View {
        let configuration: Configuration
        let kind: Kind
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .font(Tokens.text(kind == .quiet ? .body : .callout, .semibold))
                .foregroundStyle(kind == .primary ? Tokens.onAccent : (kind == .quiet && !hover ? Tokens.ink2 : Tokens.ink))
                .frame(maxWidth: kind == .quiet ? nil : .infinity)
                .padding(.horizontal, Space.m).frame(height: kind == .quiet ? 32 : 44)
                .background(Capsule().fill(fill))
                .opacity(enabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(reduceMotion ? nil : Motion.out(0.14), value: configuration.isPressed)
                .animation(Motion.hover, value: hover)
                .onHover { hover = $0 }
                .contentShape(Capsule())
        }
        var fill: Color {
            switch kind {
            case .primary: return hover ? Tokens.accent.opacity(0.9) : Tokens.accent
            case .secondary: return Color.white.opacity(hover ? 0.18 : 0.12)
            case .quiet: return Color.white.opacity(hover ? 0.08 : 0)
            }
        }
    }
}

/// A short fact under the explanation field.
struct ShieldChip: View {
    var symbol: String
    var text: String
    var body: some View {
        HStack(spacing: 5) { Image(systemName: symbol).font(Tokens.symbol(10, .semibold)); Text(text).monospacedDigit() }
            .font(Tokens.text(.caption, .medium)).foregroundStyle(Tokens.ink2)
            .padding(.horizontal, Space.xs).frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .accessibilityElement(children: .combine)
    }
}

/// Why the last explanation did not pass, or what Focus did about it: amber, with a full edge, never a side stripe.
struct ShieldNotice: View {
    var text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Tokens.slip)
            Text(text).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.slip.opacity(0.14)))
        .overlay { RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).strokeBorder(Tokens.slip.opacity(0.35)) }
        .accessibilityElement(children: .combine)
    }
}

/// Press and hold to go back to the task. Native AppKit, not a SwiftUI gesture: mouse down and up reach it directly, even when
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
        setAccessibilityLabel("Hold to go back to task")
        setAccessibilityHelp("Takes \(Int(Shield.backHoldSeconds)) seconds of holding. With VoiceOver, activating it starts the hold for you.")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) { press() }
    override func mouseUp(with event: NSEvent) { release() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { release() } }

    /// VoiceOver cannot hold a mouse button, so activating the button starts the same hold and it runs its course.
    override func accessibilityPerformPress() -> Bool { c.beginBackHold(); startRedraw(); return true }

    func press() { pressed = true; c.beginBackHold(); startRedraw(); needsDisplay = true }
    func release() { pressed = false; c.endBackHold(); stopRedrawIfIdle(); needsDisplay = true }

    private func startRedraw() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; self.c.updateBackHold(); self.needsDisplay = true; self.stopRedrawIfIdle() }
        }
    }
    private func stopRedrawIfIdle() { if c.backHoldStart == nil { timer?.invalidate(); timer = nil } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds, radius = r.height / 2   // a capsule, like the shield's other buttons
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let ink = dark ? NSColor(srgbRed: 0.93, green: 0.95, blue: 0.94, alpha: 1) : NSColor(srgbRed: 0.09, green: 0.11, blue: 0.09, alpha: 1)
        let track = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        let accent = dark ? NSColor(srgbRed: 0.47, green: 0.84, blue: 0.62, alpha: 1) : NSColor(srgbRed: 0.106, green: 0.459, blue: 0.282, alpha: 1)
        // It is the way back, so it reads as the primary action before it is pressed: a green track that fills as you hold.
        accent.withAlphaComponent(0.2).setFill(); track.fill()
        let p = CGFloat(c.backHoldProgress())
        if p > 0 {
            NSGraphicsContext.saveGraphicsState(); track.addClip()
            accent.withAlphaComponent(dark ? 0.6 : 0.35).setFill()
            NSRect(x: 0, y: 0, width: r.width * p, height: r.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        accent.withAlphaComponent(0.55).setStroke(); track.lineWidth = 1; track.stroke()
        let label = (p > 0 ? "Keep holding" : "Hold to go back to task") as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14 * TextScale.shared.factor, weight: .semibold), .foregroundColor: ink]
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            // A dim that is darkest at the edges, so the eye lands on the column in the middle.
            RadialGradient(colors: [.black.opacity(0.6), .black.opacity(0.8)], center: .center, startRadius: 80, endRadius: 900)
            // A soft pool of shade under the column, so its words read even over a bright window behind the blur.
            RadialGradient(colors: [.black.opacity(0.45), .black.opacity(0)], center: .center, startRadius: 0, endRadius: 420)
            if let s = c.shield {
                ShieldCard(c: c, shield: s)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)).combined(with: AnyTransition(.blurReplace)))
            }
        }
        .animation(reduceMotion ? Motion.reduced : Motion.out(0.32), value: c.shield?.kind)
        .animation(reduceMotion ? Motion.reduced : Motion.out(0.22), value: c.shield?.asking)
        .environment(\.colorScheme, .dark)
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
        // The shield is always dark (ShieldContent); AppKit parts such as the hold control follow the panel's appearance.
        p.appearance = NSAppearance(named: .darkAqua)
        p.onEscape = { [weak self] in if self?.c.prefs.holdToReturn != true { self?.c.shieldBackToTask() } }
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
