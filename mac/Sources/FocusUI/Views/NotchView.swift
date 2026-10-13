import SwiftUI
import FocusBrain

public enum NotchMode: Equatable, Sendable { case rest, open, nudge }

/// Size of the notch surface for each mode. Pure, so it is tested; the AppKit panel just applies it.
public enum NotchLayout {
    public static let ear: CGFloat = 66
    public static func size(_ mode: NotchMode, notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        if notchWidth == 0 {   // Macs without a notch: a floating pill under the menu bar
            switch mode { case .rest: return CGSize(width: 220, height: 36); case .open: return CGSize(width: 320, height: 118); case .nudge: return CGSize(width: 320, height: 126) }
        }
        let base = notchWidth + 2 * ear
        switch mode {
        case .rest: return CGSize(width: base, height: notchHeight)
        case .open: return CGSize(width: max(base, 330), height: notchHeight + 88)
        case .nudge: return CGSize(width: max(base, 330), height: notchHeight + 96)
        }
    }
}

extension NotchLayout {
    /// The window never resizes with the mode: it stays as big as the biggest mode and the black shape grows inside it, so the
    /// animation is SwiftUI's and AppKit's layout is never touched while it runs.
    public static func panelSize(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        let all = [NotchMode.rest, .open, .nudge].map { size($0, notchWidth: notchWidth, notchHeight: notchHeight) }
        return CGSize(width: all.map(\.width).max() ?? 0, height: all.map(\.height).max() ?? 0)
    }
}

struct NotchShape: Shape {
    var bottom: CGFloat, top: CGFloat
    var animatableData: CGFloat { get { bottom } set { bottom = newValue } }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.maxX - bottom, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - bottom), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Shared hover state, owned by the panel controller so it can resize the window itself. The window is never sized by SwiftUI:
/// letting a hosting view size a window that touches the top of a notched screen loops (the safe area changes with the size).
@MainActor @Observable
public final class NotchModel {
    public var hover = false
    public init() {}
}

/// The notch presence. Aesthetic, not functional (owner, 2026-10-01): a ring and the time at rest, and when opened only the
/// task and two buttons. A nudge opens it once with one action. It always draws dark so it melts into the hardware notch.
public struct NotchView: View {
    @Bindable var c: SessionController
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var forced: NotchMode?
    var openApp: () -> Void
    @Bindable var model: NotchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(controller: SessionController, notchWidth: CGFloat, notchHeight: CGFloat, forced: NotchMode? = nil, model: NotchModel? = nil, openApp: @escaping () -> Void) {
        self.c = controller; self.notchWidth = notchWidth; self.notchHeight = notchHeight; self.forced = forced; self.model = model ?? NotchModel(); self.openApp = openApp
    }

    static let ink = Color(red: 0.93, green: 0.95, blue: 0.94)
    static let ink2 = Color(red: 0.70, green: 0.73, blue: 0.71)
    static let accent = Color(red: 0.47, green: 0.84, blue: 0.62)

    /// A nudge opens the notch once; otherwise hover decides. The gate (strict pause screen) is not shown here.
    public static func mode(for c: SessionController, hover: Bool) -> NotchMode {
        if c.checkIn != nil || c.rhythmPrompt != nil { return .nudge }
        if let s = c.surface, s.kind != "gate" { return .nudge }
        return hover ? .open : .rest
    }
    public var mode: NotchMode { forced ?? Self.mode(for: c, hover: model.hover) }
    var tint: Color { c.ringColor == Tokens.accent ? Self.accent : Self.ink }
    var hasNotch: Bool { notchWidth > 0 }

    public var body: some View {
        let size = NotchLayout.size(mode, notchWidth: notchWidth, notchHeight: notchHeight)
        let box = NotchLayout.panelSize(notchWidth: notchWidth, notchHeight: notchHeight)
        let shape: AnyShape = hasNotch ? AnyShape(NotchShape(bottom: mode == .rest ? 12 : 22, top: 0)) : AnyShape(RoundedRectangle(cornerRadius: mode == .rest ? 18 : 24, style: .continuous))
        ZStack(alignment: .top) {
            shape.fill(.black)
            content.frame(width: size.width, height: size.height, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .frame(width: box.width, height: box.height, alignment: .top)
        .ignoresSafeArea()
        .foregroundStyle(Self.ink)
        // A short spring, a little under critical damping: the shape settles without wobbling. Reduce Motion gets a plain fade of the size.
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86), value: mode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus, \(c.presenceLabel), \(c.taskName)")
    }

    /// The band stays put while the body underneath fades in and out, so the ring and time never jump.
    @ViewBuilder var content: some View {
        VStack(spacing: 0) {
            if hasNotch { band } else if mode == .rest { rest }
            switch mode {
            case .rest: EmptyView()
            case .open: openBody.transition(.opacity.combined(with: .offset(y: -4)))
            case .nudge: nudgeBody.transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }

    /// The top band: ring on the left ear, the hardware notch in the middle, the time on the right ear.
    var band: some View {
        HStack(spacing: 0) {
            ring.frame(width: NotchLayout.ear)
            Spacer(minLength: hasNotch ? notchWidth : 0)
            time.frame(width: NotchLayout.ear)
        }
        // Fixed at the resting width, so the ring and the time stay put while the shape grows around them.
        .frame(width: hasNotch ? notchWidth + 2 * NotchLayout.ear : nil, height: hasNotch ? notchHeight : 0)
    }

    /// The resting pill on a screen without a notch.
    var rest: some View {
        HStack(spacing: 10) {
            ring.frame(width: 20)
            Text(c.taskName).font(Tokens.text(13, .medium)).lineLimit(1)
            Spacer(minLength: 4)
            time
        }.padding(.horizontal, 14).frame(maxHeight: .infinity)
    }

    var ring: some View { RingView(c.ringState, color: tint).frame(width: 18, height: 18) }
    var time: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in Text(c.clockText()).font(Tokens.rounded(13, .semibold)).monospacedDigit() }
    }

    var openBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.taskName).font(Tokens.rounded(15, .semibold)).lineLimit(1)
                    Text(c.presenceLabel).font(Tokens.text(12)).foregroundStyle(Self.ink2)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                pill(c.isPaused ? "Resume" : "Pause") { c.act(c.isPaused ? .resume : .pause) }
                pill("Open Focus") { openApp() }
            }
        }.padding(.horizontal, 18).padding(.top, hasNotch ? 6 : 12).padding(.bottom, 14)
    }

    var nudgeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(nudgeText).font(Tokens.rounded(15, .semibold)).lineLimit(2)
            HStack(spacing: 8) {
                if let p = c.rhythmPrompt, c.checkIn == nil, c.surface == nil {
                    switch p.kind {
                    case .checkIn:
                        pill("Yes, keep going", primary: true) { c.rhythmKeepGoing() }
                        pill("Take a break") { c.rhythmTakeBreak() }
                    case .breakDue(let m):
                        pill("Start \(m) min break", primary: true) { c.rhythmTakeBreak() }
                        pill("Five more minutes") { c.rhythmKeepGoing() }
                    }
                } else if c.checkIn != nil {
                    pill("Back to task", primary: true) { c.answerCheckIn(onTask: false) }
                    pill("Yes, I am") { c.answerCheckIn(onTask: true) }
                } else if c.longDetour {
                    pill(NudgeCopy.shortBreakButton(), primary: true) { c.takeNudgeBreak() }
                    pill("Back to task") { c.act(.backToTask) }
                } else {
                    pill("Back to task", primary: true) { c.act(.backToTask) }
                    pill("Not now") { c.act(.dismiss) }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.top, hasNotch ? 6 : 12).padding(.bottom, 14)
    }

    var nudgeText: String {
        if c.checkIn != nil { return NudgeCopy.checkInTitle(task: c.taskName) }
        if c.surface == nil, let p = c.rhythmPrompt { return CueCopy.rhythmTitle(p.kind, task: c.taskName) }
        return c.nudgeTitle
    }

    func pill(_ title: String, primary: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Tokens.text(12.5, .semibold)).foregroundStyle(primary ? Color(red: 0.02, green: 0.1, blue: 0.05) : Self.ink)
                .padding(.horizontal, 14).frame(height: 28)
                .background(Capsule().fill(primary ? Self.accent : Color.white.opacity(0.14)))
        }.buttonStyle(.plain)
    }
}
