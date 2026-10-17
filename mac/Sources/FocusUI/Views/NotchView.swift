import SwiftUI
import FocusBrain

/// rest: the ring and the time on either side of the hardware notch. peek: the pointer is on it, so the ears widen and say how Focus
/// reads you. open: a click opened the full card. nudge: Focus opened it to ask you back.
public enum NotchMode: Equatable, Sendable { case rest, peek, open, nudge }

/// Size of the notch surface for each mode. Pure, so it is tested; the AppKit panel just applies it.
/// Slim on purpose (owner, 2026-10-16: "not fat and big"): at rest each ear holds only the ring or the time, hover widens it just
/// enough for a two-word state, and a nudge or the open card stays under about 420 pt, so it reads as part of the bezel, not a panel.
public enum NotchLayout {
    /// Each ear beside the hardware notch at rest: room for the ring, or for the clock up to "1:05:30".
    public static let ear: CGFloat = 48
    /// How much wider each ear gets on hover, or while the notch announces a change of state: the ring plus "Getting back".
    public static let peekExtra: CGFloat = 44
    /// Room around the biggest shape, so nothing is ever cut off by the window edge.
    public static let shadowPad: CGFloat = 8
    /// The open card and the nudge: width of each side beside the hardware notch, and the depth they hang below it.
    static let openEar: CGFloat = 118, openDepth: CGFloat = 92
    static let nudgeEar: CGFloat = 110, nudgeDepth: CGFloat = 50
    public static func size(_ mode: NotchMode, notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        if notchWidth == 0 {   // Macs without a notch: a floating pill under the menu bar
            switch mode {
            case .rest: return CGSize(width: 210, height: 32)
            case .peek: return CGSize(width: 250, height: 32)
            case .open: return CGSize(width: 400, height: 32 + openDepth)
            case .nudge: return CGSize(width: 400, height: 56)
            }
        }
        let base = notchWidth + 2 * ear
        switch mode {
        case .rest: return CGSize(width: base, height: notchHeight)
        case .peek: return CGSize(width: base + 2 * peekExtra, height: notchHeight + 2)
        case .open: return CGSize(width: max(notchWidth + 2 * openEar, 400), height: notchHeight + openDepth)
        case .nudge: return CGSize(width: max(notchWidth + 2 * nudgeEar, 400), height: notchHeight + nudgeDepth)
        }
    }
}

extension NotchLayout {
    /// The window never resizes with the mode: it stays as big as the biggest mode and the black shape grows inside it, so the
    /// animation is SwiftUI's and AppKit's layout is never touched while it runs.
    public static func panelSize(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        let all = [NotchMode.rest, .peek, .open, .nudge].map { size($0, notchWidth: notchWidth, notchHeight: notchHeight) }
        return CGSize(width: (all.map(\.width).max() ?? 0) + 2 * shadowPad, height: (all.map(\.height).max() ?? 0) + shadowPad)
    }

    /// What the pointer can be on without the notch closing: the shape itself (the page tabs sit inside the open card's top band).
    public static func hitSize(_ mode: NotchMode, notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        size(mode, notchWidth: notchWidth, notchHeight: notchHeight)
    }

    /// Where the shape starts and ends: the size of the hardware notch, so it grows out of it and tucks back into it. Pixels inside the
    /// notch do not exist, so at this size nothing shows. A screen without a notch has a small pill that fades.
    public static func tucked(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        notchWidth == 0 ? CGSize(width: 150, height: 30) : CGSize(width: notchWidth, height: notchHeight)
    }

    /// Corner radii per mode: (bottom corners, the concave shoulders where it meets the bezel). Both grow a little as it opens; kept
    /// modest, since big round corners made the open card look swollen.
    static func radii(_ mode: NotchMode, shown: Bool, pill: Bool) -> (bottom: CGFloat, top: CGFloat) {
        if !shown { return (8, 0) }
        if pill { return mode == .rest || mode == .peek ? (16, 0) : (22, 0) }
        switch mode {
        case .rest: return (9, 5)
        case .peek: return (11, 6)
        case .open: return (22, 12)
        case .nudge: return (20, 10)
        }
    }
}

/// The black shape. Under a hardware notch: flush with the top edge, with concave shoulders so it flows out of the bezel the way
/// the notch itself does, and rounded bottom corners. Elsewhere: a continuous rounded pill. Both radii animate with the size.
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
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + t + b, y: r.maxY), control: CGPoint(x: r.minX + t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - b), control: CGPoint(x: r.maxX - t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - t, y: r.minY))
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
    /// Where the pointer is over the panel, in the panel's points from its top-left; nil when it is elsewhere. Drives the dot field.
    public var pointer: CGPoint?
    /// False while the shape is tucked into the hardware notch: just before it grows out at the start of a session, and while it
    /// tucks back in at the end. The controller sets it; the panel only orders out once the shape is back inside.
    public var presented = false
    /// The open notch's page. It stays as you left it, as Droppy's does. Which widgets home shows is a preference (`notchWidgets`).
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
    var body: some View {
        // One stack in every state, so opening and closing only fade the black between solid and graded: there is never a moment
        // where the glass shows on its own.
        ZStack {
            if !reduceTransparency, #available(macOS 26, *) {
                Color.clear.glassEffect(.regular.tint(.black.opacity(0.45)), in: Rectangle())
            }
            Color.black.opacity(expanded && glassy ? 0 : 1)
            GeometryReader { g in
                let stop = min(0.75, (notchHeight + 14) / max(1, g.size.height))
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: stop), .init(color: .black.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .opacity(expanded && glassy ? 1 : 0)
        }
        .clipShape(shape)
        .animation(Motion.out(0.3), value: expanded)
    }
    var glassy: Bool { if #available(macOS 26, *) { return !reduceTransparency } else { return false } }
}

/// The notch presence. Aesthetic, not functional (owner, 2026-10-01), and since 2026-10-13 not a way out either: it only shows.
/// At rest a ring and the time; under the pointer the ears widen and say how Focus reads you; a click opens the task, the clock and
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
    /// The ears are wide: under the pointer, or while a change of state is announced.
    var wide: Bool { mode == .peek || (mode == .rest && flash != nil) }

    public var body: some View {
        let shown = forced != nil || model.presented
        let sizeMode: NotchMode = mode == .rest && flash != nil ? .peek : mode
        let size = shown ? NotchLayout.size(sizeMode, notchWidth: notchWidth, notchHeight: notchHeight) : NotchLayout.tucked(notchWidth: notchWidth, notchHeight: notchHeight)
        let r = NotchLayout.radii(sizeMode, shown: shown, pill: !hasNotch)
        let shape = NotchShape(bottom: r.bottom, top: r.top, pill: !hasNotch)
        let box = NotchLayout.panelSize(notchWidth: notchWidth, notchHeight: notchHeight)
        surface(shape: shape, size: size, box: box, shown: shown)
        // Mouse down squeezes it in from the sides before it springs open, the press Droppy gives.
        .scaleEffect(x: pressing && !big && !reduceMotion ? 0.87 : 1, y: 1, anchor: .top)
        .onChange(of: model.dropTargeted) { _, on in if on { model.tab = .tray } }
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
        .accessibilityLabel("Focus, \(c.presenceLabel), \(c.taskName)")
        .accessibilityAction(named: big ? "Close" : "Show details") { if forced == nil, mode != .nudge { model.expanded.toggle() } }
    }

    /// The shape and what is in it, at its current size, before the press, bump and placement in the panel.
    func surface(shape: NotchShape, size: CGSize, box: CGSize, shown: Bool) -> some View {
        let open = shown && big
        let dotOrigin = CGPoint(x: (box.width - size.width) / 2, y: 0)
        return ZStack(alignment: .top) {
            // A nudge stays solid black, like the hardware notch it hangs from; only the open card melts into glass.
            NotchMaterial(shape: shape, expanded: open && mode == .open, notchHeight: hasNotch ? notchHeight : 0)
            if open && mode == .open { DotField(model: model, origin: dotOrigin).transition(.opacity.animation(Motion.out(0.3))) }
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
        .overlay { shape.stroke(Color.white.opacity(open ? 0.08 : 0), lineWidth: 1) }
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
                           removal: AnyTransition.opacity.combined(with: AnyTransition(.blurReplace)).animation(Motion.out(0.12)))
    }

    /// The band stays put while the body underneath fades in and out, so the ring and time never jump.
    @ViewBuilder var content: some View {
        VStack(spacing: 0) {
            if hasNotch { band } else if !big { rest } else if mode == .open { openHeader.frame(height: 32) }
            switch mode {
            case .rest, .peek: EmptyView()
            case .open: openBody.transition(bodyTransition)
            case .nudge: nudgeBody.transition(bodyTransition)
            }
        }
    }

    /// The top band: ring on the left ear, the hardware notch in the middle, the time on the right ear. Wider under the pointer,
    /// with how Focus reads you beside the ring. Open, the band carries the state and the page tabs instead, so nothing hangs below.
    var band: some View {
        // Over a nudge the ring and the time move out to the row's edges, so they line up with the words and the button below.
        let edges = mode == .nudge
        let earW = wide ? NotchLayout.ear + NotchLayout.peekExtra
            : edges ? (NotchLayout.size(.nudge, notchWidth: notchWidth, notchHeight: notchHeight).width - notchWidth) / 2 : NotchLayout.ear
        return ZStack {
            HStack(spacing: 0) {
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
            .blur(radius: mode == .open && !reduceMotion ? 4 : 0)
            if mode == .open {
                openHeader.frame(width: NotchLayout.size(.open, notchWidth: notchWidth, notchHeight: notchHeight).width, height: notchHeight)
                    .transition(bodyTransition)
            }
        }
    }

    /// The open card's top line: the ring and the state word on the left, the page tabs on the right, the hardware notch between.
    var openHeader: some View {
        HStack(spacing: 6) {
            ring
            Text(c.presenceLabel).font(Tokens.fixed(.caption, .semibold)).foregroundStyle(tint).lineLimit(1).fixedSize()
                .contentTransition(.interpolate)
            Spacer(minLength: hasNotch ? notchWidth : 8)
            ShelfTabBar(model: model)
        }
        .padding(.leading, hasNotch ? 20 : 14).padding(.trailing, hasNotch ? 16 : 10)
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
    }
    var time: some View {
        TimelineView(.everySecond) { _ in
            let t = c.clockText()
            Text(t).font(Tokens.fixed(.caption, .semibold, rounded: true)).monospacedDigit().fixedSize()
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

    /// The open card is the page the tab bar has picked: home (the session and a widget), the file tray, or the widgets.
    var openBody: some View {
        ZStack {
            switch model.tab {
            case .home: ShelfHome(c: c, model: model, tray: tray, tint: tint).transition(pageTransition)
            case .tray: TrayColumn(tray: tray, targeted: model.dropTargeted).transition(pageTransition)
            case .widgets: ShelfWidgets(c: c).transition(pageTransition)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .motion(Motion.notchSettle, value: model.tab)
        // Clear of the concave shoulders (12 pt) and the rounded foot, so nothing sits on the curve.
        .padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 14)
    }

    /// Pages swap in place: the old one blurs away as the new one sharpens in.
    var pageTransition: AnyTransition { reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .scale(scale: 0.97)) }

    // MARK: nudge: one way forward, no way out

    /// The words, one line of what Focus saw under them, and the one button. On a screen without a notch the pill has no band, so the
    /// state ring leads. The rows sit centred in the space under the band, clear of the rounded foot.
    var nudgeBody: some View {
        HStack(alignment: .center, spacing: 10) {
            if !hasNotch { nudgeMark.frame(width: 18, height: 18) }
            VStack(alignment: .leading, spacing: 2) {
                Text(nudgeText).font(Tokens.fixed(.body, .semibold)).lineLimit(1).truncationMode(.tail)
                nudgeMeta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if offersWayBack { pill("Back to task") { c.act(.backToTask) } }
        }
        .padding(.leading, hasNotch ? 22 : 16).padding(.trailing, hasNotch ? 14 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, hasNotch ? 4 : 0)
        // Green light rises from the foot of the notch as the nudge opens: it says "look here" without a sound or a flash. The shape clips it.
        .background { Halftone(pattern: .nudge, ripple: .onAppear, followsPointer: false).allowsHitTesting(false) }
    }

    var nudgeText: String {
        if c.checkIn != nil { return NudgeCopy.checkInTitle(task: c.taskName) }
        if c.surface == nil, let p = c.rhythmPrompt { return CueCopy.rhythmTitle(p.kind, task: c.taskName) }
        return c.nudgeTitle
    }

    /// A warning or the check-in: going back is the answer the notch can give. A schedule prompt is answered on the banner or in the menu bar.
    var offersWayBack: Bool { c.surface != nil || c.checkIn != nil }

    @ViewBuilder var nudgeMark: some View {
        if offersWayBack { RingView(.drift, color: Tokens.Notch.slip) }
        else { RingView(c.rhythmPrompt?.kind.ring ?? .on, color: Self.accent) }
    }

    @ViewBuilder var nudgeMeta: some View {
        HStack(spacing: 5) {
            if c.checkIn != nil {
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
