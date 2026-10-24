import SwiftUI
import AppKit
import FocusBrain

/// rest: the ring and the time on either side of the hardware notch. peek: the pointer is on it, so the ears widen a little, as
/// Droppy's do. open: a click opened the full card. nudge: Hushd opened it to ask you back.
public enum NotchMode: Equatable, Sendable { case rest, peek, open, nudge }

/// Size of the notch surface for each mode. Pure, so it is tested; the AppKit panel just applies it.
/// Droppy's own measurements (Droppy 16.0.1 on a 14-inch MacBook Pro, 2026-10-24, owner: "exact same visuals to the droppy dynamic
/// island"), taken from its window at 2x: at rest the body is 259 x 32 pt, on hover 285 x 35, and open 485 x 196, each with the concave
/// shoulders added to its top width. The open card is a fixed size, whatever the hardware notch; the tabs hang under it as a separate
/// glass pill (see `tabPill`). The nudge is Hushd's own and keeps its slim two-ear shape.
public enum NotchLayout {
    /// Each ear beside the hardware notch at rest, shoulders included: the ring, or the clock up to "1:05:30" a little smaller.
    public static let ear: CGFloat = 46
    /// How much wider each ear gets on hover: Droppy's hover is a plain widen of 13 pt a side.
    public static let hoverExtra: CGFloat = 13
    /// How much wider each ear gets while the notch announces a change of state: the ring plus "Getting back".
    public static let peekExtra: CGFloat = 44
    /// Room around the biggest shape, so nothing is ever cut off by the window edge.
    public static let shadowPad: CGFloat = 8
    /// The open card, as one fixed size: top width (body 485 plus a 27.5 pt shoulder each side) and height under the screen's top edge.
    static let openWidth: CGFloat = 541, openHeight: CGFloat = 196
    /// The open card's concave shoulder: the 485 pt body sits between the two.
    static let shoulderOpen: CGFloat = 27.5
    /// The tab pill under the open card: the gap between them, and the pill's height.
    static let pillGap: CGFloat = 12.5, pillHeight: CGFloat = 29
    /// The nudge: width of each side beside the hardware notch, and the depth it hangs below it.
    static let nudgeEar: CGFloat = 110, nudgeDepth: CGFloat = 50
    public static func size(_ mode: NotchMode, notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        if notchWidth == 0 {   // Macs without a notch: a floating pill under the menu bar
            switch mode {
            case .rest: return CGSize(width: 210, height: 32)
            case .peek: return CGSize(width: 236, height: 35)
            case .open: return CGSize(width: openWidth - 56, height: openHeight)
            case .nudge: return CGSize(width: 400, height: 56)
            }
        }
        let base = notchWidth + 2 * ear
        switch mode {
        case .rest: return CGSize(width: base, height: notchHeight)
        case .peek: return CGSize(width: base + 2 * hoverExtra, height: notchHeight + 3)
        case .open: return CGSize(width: openWidth, height: openHeight)
        case .nudge: return CGSize(width: max(notchWidth + 2 * nudgeEar, 400), height: notchHeight + nudgeDepth)
        }
    }

    /// The rest shape while a change of state is announced: the ears open wide enough for the ring and a two-word state.
    public static func announcing(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        notchWidth == 0 ? CGSize(width: 250, height: 32) : CGSize(width: notchWidth + 2 * (ear + peekExtra), height: notchHeight + 2)
    }
}

extension NotchLayout {
    /// The window never resizes with the mode: it stays as big as the biggest mode and the black shape grows inside it, so the
    /// animation is SwiftUI's and AppKit's layout is never touched while it runs. The open card's tab pill hangs inside it.
    public static func panelSize(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        let all = [NotchMode.rest, .peek, .open, .nudge].map { size($0, notchWidth: notchWidth, notchHeight: notchHeight) }
        return CGSize(width: (all.map(\.width).max() ?? 0) + 2 * shadowPad, height: (all.map(\.height).max() ?? 0) + pillGap + pillHeight + shadowPad)
    }

    /// What the pointer can be on without the notch closing: the shape itself, and while it is open the gap under it and the tab pill,
    /// so moving down to the tabs does not close the card.
    public static func hitSize(_ mode: NotchMode, notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        let s = size(mode, notchWidth: notchWidth, notchHeight: notchHeight)
        return mode == .open ? CGSize(width: s.width, height: s.height + pillGap + pillHeight) : s
    }

    /// Where the black ends and the glass begins, as a share of the open card's height: Droppy keeps its top 61 percent solid (240 of 392
    /// px in its capture) and fades to glass over the rest. A card too short to show that (the nudge) keeps a band under the hardware notch.
    static func blackStop(height: CGFloat, notchHeight: CGFloat) -> CGFloat {
        height >= openHeight - 1 ? 0.61 : min(0.75, (notchHeight + 14) / max(1, height))
    }

    /// Where the shape starts and ends: the size of the hardware notch, so it grows out of it and tucks back into it. Pixels inside the
    /// notch do not exist, so at this size nothing shows. A screen without a notch has a small pill that fades.
    public static func tucked(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        notchWidth == 0 ? CGSize(width: 150, height: 30) : CGSize(width: notchWidth, height: notchHeight)
    }

    /// Corner radii per mode: (bottom corners, the concave shoulders where it meets the bezel). Droppy's, measured: its shoulders and
    /// bottom corners grow together as it opens.
    static func radii(_ mode: NotchMode, shown: Bool, pill: Bool) -> (bottom: CGFloat, top: CGFloat) {
        if !shown { return (8, 0) }
        if pill { return mode == .rest || mode == .peek ? (16, 0) : (28, 0) }
        switch mode {
        case .rest: return (8.5, 6)
        case .peek: return (9, 7)
        case .open: return (35, 27.5)
        case .nudge: return (24, 14)
        }
    }
}

/// The black shape. Under a hardware notch: flush with the top edge, with concave shoulders so it flows out of the bezel the way
/// the notch itself does, and rounded bottom corners, all true circular arcs as Droppy's are. Elsewhere: a continuous rounded pill.
/// Both radii animate with the size.
struct NotchShape: Shape {
    var bottom: CGFloat, top: CGFloat
    var pill = false
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottom, top) }
        set { bottom = newValue.first; top = newValue.second }
    }
    func path(in r: CGRect) -> Path {
        if pill { return RoundedRectangle(cornerRadius: bottom, style: .continuous).path(in: r) }
        let t = min(top, r.width / 4), b = min(bottom, (r.width - 2 * t) / 2, r.height - t)
        let k: CGFloat = 0.5523   // a cubic Bezier's control distance for a quarter circle
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control1: CGPoint(x: r.minX + k * t, y: r.minY), control2: CGPoint(x: r.minX + t, y: r.minY + t - k * t))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        p.addCurve(to: CGPoint(x: r.minX + t + b, y: r.maxY), control1: CGPoint(x: r.minX + t, y: r.maxY - b + k * b), control2: CGPoint(x: r.minX + t + b - k * b, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - b), control1: CGPoint(x: r.maxX - t - b + k * b, y: r.maxY), control2: CGPoint(x: r.maxX - t, y: r.maxY - b + k * b))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY), control1: CGPoint(x: r.maxX - t, y: r.minY + t - k * t), control2: CGPoint(x: r.maxX - k * t, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Shared hover state, owned by the panel controller so it can resize the window itself. The window is never sized by SwiftUI:
/// letting a hosting view size a window that touches the top of a notched screen loops (the safe area changes with the size).
@MainActor @Observable
public final class NotchModel {
    public var hover = false
    /// A click opened the full card. Moving the pointer away closes it again.
    public var expanded = false
    /// A file is being dragged over the notch: it opens with the tray ready to take it.
    public var dropTargeted = false
    /// False while the shape is tucked into the hardware notch: just before it grows out at the start of a session, and while it
    /// tucks back in at the end. The controller sets it; the panel only orders out once the shape is back inside.
    public var presented = false
    /// The open notch's page. It stays as you left it, as Droppy's does.
    public var tab = NotchTab.home
    public init() {}
}

/// What the notch is made of. At rest it is solid black, part of the bezel. Open, it is black where it meets the hardware notch and
/// melts into Liquid Glass below, so the desktop shows through toward the bottom edge (Droppy's "Dynamic Glass").
/// Reduce Transparency, or a Mac before macOS 26, keeps it solid black.
private struct NotchMaterial: View {
    let shape: NotchShape
    let expanded: Bool
    let notchHeight: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The blur and glass are live layers the window server re-renders every frame, and masking them with a shape that is changing size
    /// costs a blurred pass per frame. So they only exist while the card holds still: they frost in once it has finished opening, and are
    /// covered by black and removed the moment it starts to close. (Both an open and a close used to hitch in their first frames.)
    @State private var settled = false
    @State private var layered = false
    var body: some View {
        // One stack in every state: the black is solid while the shape moves, and fades to the graded glass once it is still. Under the
        // black sits a real blur of whatever is behind the notch (an NSVisualEffectView forced active, since a panel that never becomes key
        // would draw it grey), then Liquid Glass on top where the Mac has it, so the lower part of the card is see-through, as iOS 27's is.
        ZStack {
            if glassy && (settled || layered) {
                if #available(macOS 26, *) { Color.clear.glassEffect(.clear, in: Rectangle()) }
            }
            // One layer, so the black only ever gets less opaque or more: a cross-fade of two black layers dips to see-through halfway,
            // which flashed grey on the way in and out.
            GlassFoot(foot: settled && glassy ? 0.12 : 1, notchHeight: notchHeight)
        }
        .clipShape(shape)
        .animation(settled ? Motion.out(0.5) : Motion.out(0.1), value: settled)
        .task(id: expanded) {
            if expanded {
                try? await Task.sleep(for: .seconds(0.4))
                if !Task.isCancelled { layered = true; settled = true }
            } else if settled {
                settled = false
                try? await Task.sleep(for: .seconds(0.14))
                if !Task.isCancelled { layered = false }
            }
        }
    }
    var glassy: Bool { if #available(macOS 26, *) { return !reduceTransparency } else { return false } }
}

/// The card's black, graded: solid where it meets the hardware notch (the top 61 percent), fading to `foot` opacity at the bottom, with the
/// sheen glass catches along its lower edge. `foot` animates, so the card turns from solid black to glass and back without a flash.
struct GlassFoot: View, Animatable {
    var foot: Double
    var notchHeight: CGFloat
    var animatableData: Double { get { foot } set { foot = newValue } }
    var body: some View {
        GeometryReader { g in
            let stop = NotchLayout.blackStop(height: g.size.height, notchHeight: notchHeight)
            ZStack {
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: stop), .init(color: .black.opacity(foot), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.55), .init(color: .white.opacity(0.16 * (1 - foot) / 0.88), location: 1)],
                               startPoint: .top, endPoint: .bottom).blendMode(.plusLighter)
            }
        }
    }
}

/// A blur of what is behind the window, always drawn as active (a notch panel is never the key window).
struct NotchBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active; v.isEmphasized = false
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// The notch presence. Aesthetic, not functional (owner, 2026-10-01), and since 2026-10-13 not a way out either: it only shows.
/// At rest a ring and the time; under the pointer the ears widen a little; a click opens the task, the clock and
/// today's progress; a nudge says what it says and offers one button, "Back to task". There is no way to step away from a nudge here,
/// because anything like that lives in the app window, where it can be checked (the shield) or at least be seen.
/// It always draws dark so it melts into the hardware notch.
public struct NotchView: View {
    @Bindable var c: SessionController
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var forced: NotchMode?
    @Bindable var model: NotchModel
    var tray: NotchTray
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The state word the notch is announcing, for a couple of seconds after it changes. Nil the rest of the time.
    @State private var flash: String?
    @State private var flashTask: Task<Void, Never>?
    /// The mouse is down on the shape: it squeezes in, and springs open when the click lands.
    @GestureState private var pressing = false

    public init(controller: SessionController, notchWidth: CGFloat, notchHeight: CGFloat, forced: NotchMode? = nil, model: NotchModel? = nil, tray: NotchTray? = nil) {
        self.c = controller; self.notchWidth = notchWidth; self.notchHeight = notchHeight; self.forced = forced; self.model = model ?? NotchModel()
        self.tray = tray ?? NotchTray()
    }

    static let ink = Tokens.Notch.ink
    static let ink2 = Tokens.Notch.ink2
    static let accent = Tokens.Notch.accent
    static let track = Color.white.opacity(0.16)

    /// One drift, one popup. The banner over your window carries the nudge, and the notch opening to the same words at the same time
    /// overlapped it under the menu bar. So the notch opens to a nudge only when the banner is off in Settings; otherwise its ring turns amber.
    /// The gate (strict pause screen) is never shown here.
    public static func opensToNudge(_ c: SessionController) -> Bool {
        if c.heldCheckInAt != nil { return true }   // the pause note: no banner is up while paused, and it has no buttons
        guard !c.prefs.showBanner else { return false }
        return c.checkIn != nil || c.rhythmPrompt != nil || (c.surface.map { $0.kind != "gate" } ?? false)
    }

    /// A nudge opens the notch once (see `opensToNudge`); otherwise a click opens it and hover peeks.
    public static func mode(for c: SessionController, hover: Bool, expanded: Bool = false, dropping: Bool = false) -> NotchMode {
        if dropping { return .open }   // a file on its way gets the tray, even over a nudge; the nudge is back once it lands
        if opensToNudge(c) { return .nudge }
        if expanded { return .open }
        return hover ? .peek : .rest
    }
    public var mode: NotchMode { forced ?? Self.mode(for: c, hover: model.hover, expanded: model.expanded, dropping: model.dropTargeted) }
    /// Green on task, amber once a slip is called (the banner's color), white otherwise; drifting stays white, since it may be nothing.
    var tint: Color { c.ringColor == Tokens.accent ? Self.accent : c.presence.state == "interrupted" ? Tokens.Notch.slip : Self.ink }
    var hasNotch: Bool { notchWidth > 0 }
    var big: Bool { mode == .open || mode == .nudge }
    /// The ears are wide enough for a word: while a change of state is announced. Hovering only widens them a little.
    var wide: Bool { mode == .rest && flash != nil }
    /// You paused it yourself: the ears keep their size, show the pause mark, and count how long it has been instead of a frozen clock.
    var pausedByYou: Bool { c.isHeld && SessionController.asksAboutHold(c.presence.reason) }

    public var body: some View {
        let shown = forced != nil || model.presented
        let size = !shown ? NotchLayout.tucked(notchWidth: notchWidth, notchHeight: notchHeight)
            : wide ? NotchLayout.announcing(notchWidth: notchWidth, notchHeight: notchHeight)
            : NotchLayout.size(mode, notchWidth: notchWidth, notchHeight: notchHeight)
        let r = NotchLayout.radii(wide ? .peek : mode, shown: shown, pill: !hasNotch)
        let shape = NotchShape(bottom: r.bottom, top: r.top, pill: !hasNotch)
        let box = NotchLayout.panelSize(notchWidth: notchWidth, notchHeight: notchHeight)
        surface(shape: shape, size: size, box: box, shown: shown)
        .overlay(alignment: .top) { tabPill(shown: shown, height: size.height) }
        // Mouse down squeezes it in from the sides before it springs open, the press Droppy gives.
        .scaleEffect(x: pressing && !big && !reduceMotion ? 0.87 : 1, y: 1, anchor: .top)
        .onChange(of: model.dropTargeted) { _, on in if on { model.tab = .tray; haptic(.entered) } }
        // One tap for each thing you do to it, never for what it does on its own (a nudge has its own cue) or for hovering.
        .onChange(of: pressing) { _, down in if down && !big { haptic(.pressed) } }
        .onChange(of: model.expanded) { _, open in if open { haptic(.opened) } }
        .onChange(of: model.tab) { _, _ in if big { haptic(.page) } }
        .onChange(of: tray.drops) { _, _ in haptic(.landed) }
        .frame(width: box.width, height: box.height, alignment: .top)
        .ignoresSafeArea()
        .foregroundStyle(Self.ink)
        .animation(morph(shown: shown), value: mode)
        .animation(morph(shown: shown), value: shown)
        .animation(reduceMotion ? Motion.reduced : Motion.notchPeek, value: flash)
        .animation(reduceMotion ? nil : Motion.notchPress, value: pressing)
        // A file landing gives the whole shape a small bump, so the drop is felt as well as seen.
        .keyframeAnimator(initialValue: 1.0, trigger: tray.drops) { content, k in content.scaleEffect(reduceMotion ? 1 : k, anchor: .top) } keyframes: { _ in
            SpringKeyframe(1.035, duration: 0.12, spring: .init(response: 0.12, dampingRatio: 0.9))
            SpringKeyframe(1, duration: 0.45, spring: .init(response: 0.35, dampingRatio: 0.6))
        }
        .onChange(of: c.presenceLabel) { _, label in announce(label) }
        .onDisappear { flashTask?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hushd, \(c.presenceLabel), \(c.taskName)")
        .accessibilityAction(named: big ? "Close" : "Show details") { if forced == nil, mode != .nudge { model.expanded.toggle() } }
    }

    /// The shape and what is in it, at its current size, before the press, bump and placement in the panel.
    func surface(shape: NotchShape, size: CGSize, box: CGSize, shown: Bool) -> some View {
        let open = shown && big
        return ZStack(alignment: .top) {
            // A nudge stays solid black, like the hardware notch it hangs from; only the open card melts into glass.
            NotchMaterial(shape: shape, expanded: open && mode == .open, notchHeight: hasNotch ? notchHeight : 0)
            content.frame(width: size.width, height: size.height, alignment: .top)
                .opacity(shown ? 1 : 0)
                .blur(radius: shown || reduceMotion ? 0 : 6)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .contentShape(shape)
        // Closed, a click anywhere on the shape opens it. Open, the click belongs to what is under it (tabs, widgets, files), and
        // the notch closes when the pointer leaves, as Droppy's does.
        .gesture(press, including: big ? .subviews : .all)
        // Light catching the rim of the glass, only once it has opened out of the bezel.
        .overlay {
            shape.stroke(LinearGradient(colors: [.white.opacity(0.04), .white.opacity(0.1), .white.opacity(0.42)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .opacity(open && mode == .open ? 1 : 0)
        }
        .opacity(hasNotch || shown ? 1 : 0)
    }

    /// A click on the shape opens it, and a click on the open card closes it. A nudge stays open until it is answered.
    var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($pressing) { _, state, _ in state = true }
            .onEnded { v in
                guard forced == nil, mode != .nudge, abs(v.translation.width) < 6, abs(v.translation.height) < 6 else { return }
                model.expanded = true
            }
    }

    /// Widen for a moment and say the new state, then settle back. A second change while it shows just swaps the word.
    /// A tap on the trackpad, unless this is a preview or the switch is off.
    func haptic(_ kind: NotchHaptics.Kind) {
        guard forced == nil, c.prefs.notchHaptics else { return }
        NotchHaptics.play(kind)
    }

    func announce(_ label: String) {
        guard forced == nil, model.presented, c.isActive else { return }
        flash = label
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            if !Task.isCancelled { flash = nil }
        }
    }

    /// Each move has its own spring, from Droppy's measured motion: a quick widen on hover, a fuller open with a hint of overshoot,
    /// and a close with none. Reduce Motion gets a short fade of the size.
    func morph(shown: Bool) -> Animation {
        if reduceMotion { return Motion.reduced }
        if !shown { return Motion.notchTuck }
        switch mode {
        case .rest: return Motion.notchClose
        case .peek: return Motion.notchPeek
        case .open, .nudge: return Motion.notchOpen
        }
    }

    /// The card's content grows in with the shape and sharpens out of a blur as it settles, as Droppy's does. It leaves at once, so
    /// the shape never closes over words still on show.
    var bodyTransition: AnyTransition {
        if reduceMotion { return .opacity.animation(Motion.reduced) }
        return .asymmetric(insertion: AnyTransition(.blurReplace).combined(with: .scale(scale: 0.9, anchor: .top)).animation(Motion.notchOpen),
                           removal: AnyTransition.opacity.animation(Motion.out(0.1)))
    }

    /// The band stays put while the body underneath fades in and out, so the ring and time never jump.
    @ViewBuilder var content: some View {
        VStack(spacing: 0) {
            if hasNotch { band } else if !big { rest } else if mode == .open { Color.clear.frame(height: 32) }
            switch mode {
            case .rest, .peek: EmptyView()
            case .open: openBody.transition(bodyTransition)
            case .nudge: nudgeBody.transition(bodyTransition)
            }
        }
    }

    /// The top band: ring on the left ear, the hardware notch in the middle, the time on the right ear. A little wider under the pointer,
    /// and wide enough for the state word while a change is announced. Open, the band is empty, as Droppy's is: the card starts under it.
    var band: some View {
        // Over a nudge the ring and the time move out to the row's edges, so they line up with the words and the button below.
        let edges = mode == .nudge
        let earW = wide ? NotchLayout.ear + NotchLayout.peekExtra
            : mode == .peek ? NotchLayout.ear + NotchLayout.hoverExtra
            : edges ? (NotchLayout.size(.nudge, notchWidth: notchWidth, notchHeight: notchHeight).width - notchWidth) / 2 : NotchLayout.ear
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                ring
                if wide {
                    Text(flash ?? c.presenceLabel).font(Tokens.fixed(.caption2, .semibold)).foregroundStyle(tint).lineLimit(1).fixedSize()
                        .transition(earTransition(.leading))
                }
            }
            .padding(.leading, edges ? 22 : 0)
            .frame(width: earW, alignment: edges ? .leading : .center)
            Spacer(minLength: notchWidth)
            time.padding(.trailing, edges ? 16 : 0).frame(width: earW, alignment: edges ? .trailing : .center)
        }
        .frame(width: notchWidth + 2 * earW, height: notchHeight)
        .opacity(mode == .open ? 0 : 1)
    }

    /// Words in a widened ear wait for the ear to open, then come out of a blur.
    func earTransition(_ edge: UnitPoint) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: AnyTransition(.blurReplace).combined(with: .scale(scale: 0.7, anchor: edge)).animation(Motion.notchPeek.delay(0.1)),
                           removal: AnyTransition.opacity.animation(Motion.out(0.1)))
    }

    /// The resting pill on a screen without a notch.
    var rest: some View {
        HStack(spacing: 8) {
            ring
            Text(wide ? (flash ?? c.presenceLabel) : c.taskName).font(Tokens.fixed(.caption, wide ? .semibold : .medium)).lineLimit(1)
                .foregroundStyle(wide ? tint : Self.ink)
                .contentTransition(.interpolate)
            Spacer(minLength: 4)
            time
        }.padding(.horizontal, 12).frame(maxHeight: .infinity)
    }

    var ring: some View {
        // Ticks each second so a timed arc sweeps with the clock; a change of shape (drift, a pause) blurs in.
        TimelineView(.everySecond) { _ in LiveRing(c.ringState, color: tint).frame(width: 14, height: 14) }
            .scaleEffect(mode == .peek && !reduceMotion ? 1.14 : 1)
    }
    var time: some View {
        TimelineView(.everySecond) { _ in
            let t = pausedByYou ? c.heldClockText() : c.clockText()
            Text(t).font(t.count > 5 && !wide && mode != .nudge ? .system(size: 10, weight: .semibold, design: .rounded) : Tokens.fixed(.caption, .semibold, rounded: true))
                .monospacedDigit().fixedSize()
        }
    }

    // MARK: open: read only

    /// Today's time on task against the daily goal, when progress is shown and a goal is set.
    var goal: (fraction: Double, line: String)? {
        guard c.prefs.showProgress, c.prefs.dailyGoalMinutes > 0 else { return nil }
        let seconds = c.todayOnTaskSeconds(), target = Double(c.prefs.dailyGoalMinutes) * 60
        return (min(1, seconds / target), "\(Self.minutes(seconds)) of \(Self.minutes(target)) today")
    }
    static func minutes(_ s: Double) -> String {
        let m = Int((s / 60).rounded(.down))
        return m >= 60 ? (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min") : "\(m) min"
    }

    /// The open card is the page the tab pill has picked: home (the session and today), or the file tray.
    var openBody: some View {
        ZStack {
            switch model.tab {
            case .home: ShelfHome(c: c, tint: tint).transition(pageTransition)
            case .tray: TrayPage(tray: tray, targeted: model.dropTargeted).transition(pageTransition)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .motion(Motion.notchSettle, value: model.tab)
        // Clear of the concave shoulders (27.5 pt), so the 485 pt body sits between them as Droppy's does.
        .padding(.horizontal, NotchLayout.shoulderOpen).padding(.top, 0).padding(.bottom, 0)
    }

    /// Droppy's tab bar: a small glass pill under the card with an icon per page, the current one on a lighter capsule.
    @ViewBuilder func tabPill(shown: Bool, height: CGFloat) -> some View {
        let visible = shown && mode == .open
        ZStack {
            if visible {
                ShelfTabPill(model: model)
                    .offset(y: height + NotchLayout.pillGap)
                    .transition(.asymmetric(
                        insertion: (reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .scale(scale: 0.8, anchor: .top))).animation(Motion.notchOpen.delay(0.06)),
                        removal: AnyTransition.opacity.animation(Motion.out(0.08))))
            }
        }
        .animation(visible ? Motion.notchOpen.delay(0.06) : Motion.out(0.08), value: visible)
    }

    /// Pages swap in place: the old one blurs away as the new one sharpens in.
    var pageTransition: AnyTransition { reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .scale(scale: 0.97)) }

    // MARK: nudge: one way forward, no way out

    /// The words, one line of what Hushd saw under them, and the one button. On a screen without a notch the pill has no band, so the
    /// state ring leads. The rows sit centred in the space under the band, clear of the rounded foot.
    var nudgeBody: some View {
        HStack(alignment: .center, spacing: 10) {
            if !hasNotch { nudgeMark.frame(width: 18, height: 18) }
            VStack(alignment: .leading, spacing: 2) {
                Text(nudgeText).font(Tokens.fixed(.body, .semibold)).lineLimit(1).truncationMode(.tail)
                nudgeMeta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if offersWayBack { pill("Back to task") { c.act(.backToTask) }.goesTo(c.returnPlace) }
        }
        .padding(.leading, hasNotch ? 22 : 16).padding(.trailing, hasNotch ? 14 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, hasNotch ? 4 : 0)
        // Green light rises from the foot of the notch as the nudge opens: it says "look here" without a sound or a flash. The shape clips it.
        .background { Halftone(pattern: .nudge, ripple: .onAppear, followsPointer: false).allowsHitTesting(false) }
    }

    var nudgeText: String {
        if c.heldCheckInAt != nil { return CueCopy.heldTitle(seconds: c.heldSince.map { c.nowSeconds() - $0 } ?? 0) }
        if c.checkIn != nil { return NudgeCopy.checkInTitle(task: c.taskName) }
        if c.surface == nil, let p = c.rhythmPrompt { return CueCopy.rhythmTitle(p.kind, task: c.taskName) }
        return c.nudgeTitle
    }

    /// A warning or the check-in: going back is the answer the notch can give. A schedule prompt is answered on the banner or in the menu bar.
    var offersWayBack: Bool { c.surface != nil || c.checkIn != nil }

    @ViewBuilder var nudgeMark: some View {
        if c.heldCheckInAt != nil { RingView(c.ringState, color: Self.ink) }
        else if offersWayBack { RingView(.drift, color: Tokens.Notch.slip) }
        else { RingView(c.rhythmPrompt?.kind.ring ?? .on, color: Self.accent) }
    }

    @ViewBuilder var nudgeMeta: some View {
        HStack(spacing: 5) {
            if c.heldCheckInAt != nil {
                Image(systemName: "pause.fill").font(.system(size: 8, weight: .semibold)); Text(CueCopy.heldMeta)
            } else if c.checkIn != nil {
                notchSparkle; Text(CueCopy.checkInMeta)
            } else if c.surface != nil {
                notchSparkle; Text(CueCopy.reminderMeta)
                TimelineView(.everySecond) { _ in Text(BannerView.clock(c.offTopicSecondsNow())).monospacedDigit().foregroundStyle(Tokens.Notch.slip) }
            } else if let p = c.rhythmPrompt {
                Image(systemName: "clock").font(.system(size: 9, weight: .semibold))
                Text(c.prefs.showBanner ? CueCopy.rhythmMeta(p.kind, checkInMinutes: c.prefs.checkInMinutes) : "Answer in the menu bar")
            }
        }
        .font(Tokens.fixed(.caption2, .medium)).foregroundStyle(Self.ink2).lineLimit(1)
    }

    var notchSparkle: some View { Image(systemName: "sparkle").font(.system(size: 9, weight: .semibold)).foregroundStyle(Self.accent).accessibilityHidden(true) }

    /// The only button on the notch. It goes the way the app wants you to go, so it is the one thing that is safe to leave here.
    func pill(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Tokens.fixed(.caption, .semibold)).foregroundStyle(Tokens.Notch.onAccent)
                .padding(.horizontal, 12).frame(height: 26)
        }.buttonStyle(PillStyle())
    }
}

/// The notch's one button: brightens under the pointer and gives under the click, like a system control.
struct PillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @State private var hover = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .background(Capsule().fill(NotchView.accent.opacity(hover ? 1 : 0.9)))
                .overlay { Capsule().fill(.white.opacity(hover ? 0.12 : 0)).blendMode(.plusLighter) }
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
                .animation(reduceMotion ? nil : Motion.notchPress, value: configuration.isPressed)
                .animation(Motion.hover, value: hover)
                .onHover { hover = $0 }
                .contentShape(Capsule())
        }
    }
}
