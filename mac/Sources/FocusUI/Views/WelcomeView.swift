import SwiftUI
import FocusBrain

/// The welcome, once, on a new Mac: what Focus does (shown as a session, not explained), window access with a live check, and the
/// first task. Three steps laid out like the Mac's own setup assistant: the step on top, one column in the middle, Back at the bottom
/// left and the one primary action at the bottom right. Every step has a way out, and nothing here is needed to use Focus.
struct WelcomeView: View {
    @Bindable var c: SessionController
    @State var step: Int
    /// The system dialog and System Settings were opened from here, so the step says what to do there and waits.
    @State private var asked = false
    @State private var task = ""
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(c: SessionController, step: Int = 0, asked: Bool = false, task: String = "") {
        self.c = c; self._step = State(initialValue: step); self._asked = State(initialValue: asked); self._task = State(initialValue: task)
    }

    static let steps = 3
    static let column: CGFloat = 560

    var body: some View {
        VStack(spacing: 0) {
            StepDots(step: step, of: Self.steps).padding(.top, Space.l)
            // Each step starts at the same height, so the picture and title stay put as you move between steps.
            Spacer(minLength: Space.l).frame(maxHeight: 72)
            Group {
                switch step {
                case 0: intro
                case 1: access
                default: firstTask
                }
            }
            .frame(width: Self.column)
            .id(step)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: 28)), removal: .opacity.combined(with: .offset(x: -28))))
            Spacer(minLength: Space.l)
            bottomBar
        }
        .padding(.horizontal, Space.xxl).padding(.bottom, Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.window)
        .animation(reduceMotion ? Motion.reduced : Motion.out(0.3), value: step)
        .modifier(PlainTitleBar())
    }

    // MARK: step 1, what Focus does

    var intro: some View {
        VStack(spacing: Space.xl) {
            Stage { WelcomeDemo() }
            Headline(title: "Stay on the task you name",
                     line: "A gentle nudge when you drift. When Focus isn't sure, it does nothing.")
            HStack(spacing: Space.xl) {
                Fact(symbol: "lock", text: "Stays on this Mac")
                Fact(symbol: "person.slash", text: "No account")
                Fact(symbol: "pause.circle", text: "Pause any time")
            }
        }
    }

    // MARK: step 2, window access

    var allowed: Bool { c.windowAccess == .allowed }

    var access: some View {
        VStack(spacing: Space.xl) {
            Stage { AccessPicture(allowed: allowed) }
            Headline(title: "Let Focus see the window in front",
                     line: "Focus reads the app, title and page address, only during a session.")
            accessStatus.frame(minHeight: 28)
        }
    }

    @ViewBuilder var accessStatus: some View {
        if allowed {
            Label { Text("Allowed").font(Tokens.text(.body, .semibold)) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.accent) }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .accessibilityLabel("Accessibility is allowed")
        } else if asked {
            HStack(spacing: Space.xs) {
                ThinkingDot()
                Text("Switch on Focus, then come back").font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2)
            }
            .help("If Focus is already switched on in the list, remove it with the minus button and add it again.")
            .transition(.opacity)
        } else {
            Text("Without it, Focus sees only the app name").font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2)
        }
    }

    // MARK: step 3, the first task

    var parsed: (task: String, minutes: Int?) { StartSheet.parse(task) }

    var firstTask: some View {
        VStack(spacing: Space.xl) {
            Stage { MenuBarPicture(task: parsed.task, minutes: parsed.minutes) }
            Headline(title: "What are you working on?", line: "A few words is enough.")
            VStack(spacing: Space.s) {
                TextField("Lab report on pendulums", text: $task)
                    .font(Tokens.rounded(.title3, .medium))
                    .wellField(height: 56, focused: typing)
                    .focused($typing).onSubmit(startSession)
                    .onAppear { typing = true }
                Text(hint).font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if c.prefs.practiceActive {
                    Fact(symbol: "eye", text: "First \(c.prefs.practiceSessionsLeft) sessions are practice, no nudges")
                }
            }
        }
    }

    var hint: String {
        if let m = parsed.minutes { return "\(m) minutes on \u{201C}\(parsed.task)\u{201D}" }
        return "Add minutes to time it: \u{201C}Essay 25\u{201D}"
    }

    func startSession() { Self.start(c, text: task) }

    /// The welcome's last step: "Essay 25" starts a 25 minute session on "Essay", anything else an open one. Nothing happens on an empty name.
    @discardableResult static func start(_ c: SessionController, text: String, autoTick: Bool = true) -> Bool {
        let p = StartSheet.parse(text)
        guard !p.task.isEmpty else { return false }
        c.finishWelcome(explained: true)
        c.begin(task: p.task, mode: p.minutes != nil ? .timed : .open, duration: p.minutes.map { Double($0 * 60) }, autoTick: autoTick)
        return true
    }

    // MARK: the bottom bar

    var bottomBar: some View {
        HStack(spacing: Space.xs) {
            if step == 0 {
                Button("Skip setup") { c.finishWelcome(explained: false) }.buttonStyle(FocusButtonStyle(.plain))
            } else {
                Button { step -= 1 } label: { Label("Back", systemImage: "chevron.left") }.buttonStyle(FocusButtonStyle(.plain))
            }
            Spacer()
            switch step {
            case 0:
                Button("Continue") { step = 1 }.buttonStyle(FocusButtonStyle(.primary)).keyboardShortcut(.defaultAction)
            case 1:
                if allowed {
                    Button("Continue") { step = 2 }.buttonStyle(FocusButtonStyle(.primary)).keyboardShortcut(.defaultAction)
                } else {
                    Button("Not now") { step = 2 }.buttonStyle(FocusButtonStyle(.secondary))
                    Button("Open System Settings") { asked = true; c.onOpenAccessSettings?() }
                        .buttonStyle(FocusButtonStyle(.primary)).keyboardShortcut(.defaultAction)
                }
            default:
                Button("Start later") { c.finishWelcome(explained: true) }.buttonStyle(FocusButtonStyle(.secondary))
                Button("Start session", action: startSession).buttonStyle(FocusButtonStyle(.primary))
                    .disabled(parsed.task.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: 760)
        .animation(reduceMotion ? Motion.reduced : Motion.out(0.2), value: allowed)
    }
}

/// Where you are in the welcome: one capsule per step, the current one long and green. Says it in words to VoiceOver.
struct StepDots: View {
    var step: Int
    var of: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<of, id: \.self) { i in
                Capsule().fill(i == step ? Tokens.accent : Tokens.track).frame(width: i == step ? 20 : 6, height: 6)
            }
        }
        .animation(Motion.glide, value: step)
        .accessibilityElement().accessibilityLabel("Step \(step + 1) of \(of)")
    }
}

/// The raised area each step shows its picture on.
struct Stage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(Space.xl)
            .frame(maxWidth: .infinity, minHeight: 214)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).fill(Tokens.window2))
            .overlay { RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).strokeBorder(Tokens.cardEdge) }
    }
}

/// A step's title and one or two sentences, centred under its picture.
struct Headline: View {
    var title: String
    var line: String
    var body: some View {
        VStack(spacing: Space.xs) {
            Text(title).font(Tokens.rounded(.display, .semibold)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            Text(line).font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 460)
        }
    }
}

/// A symbol and a few words.
struct Fact: View {
    var symbol: String
    var text: String
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(Tokens.ink2) }
            .font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2)
    }
}

/// A made-up session that plays once: the band fills from the left and the ring above follows it, through the three calls Focus
/// makes and the return. The windows are examples. Under Reduce Motion, and in snapshots, it shows the whole session at once.
struct WelcomeDemo: View {
    struct Part {
        let call: Reading.Call, share: Double, window: String, title: String, detail: String
    }
    static let parts = [
        Part(call: .on, share: 0.32, window: "Chapter 5.pdf", title: "On task", detail: "Matches your task"),
        Part(call: .unsure, share: 0.2, window: "Messages", title: "Not sure", detail: "So it does nothing"),
        Part(call: .off, share: 0.22, window: "A video", title: "Off topic", detail: "A gentle nudge"),
        Part(call: .on, share: 0.26, window: "Chapter 5.pdf", title: "On task", detail: "You came back"),
    ]
    static let seconds = 6.5
    @State private var started = Date()
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var still: Bool { reduceMotion || SnapshotMode.on }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: done || still)) { ctx in
            let p = done || still ? 1 : min(1, ctx.date.timeIntervalSince(started) / Self.seconds)
            content(p)
        }
        .task(id: started) {
            guard !still else { return }
            try? await Task.sleep(for: .seconds(Self.seconds + 0.1))
            done = true
        }
        .accessibilityElement()
        .accessibilityLabel("An example session: on task, then not sure, which does nothing, then off topic with a gentle nudge, then back on task.")
    }

    /// Which part the fill has reached.
    static func index(at p: Double) -> Int {
        var end = 0.0
        for (i, part) in parts.enumerated() { end += part.share; if p < end - 0.0001 { return i } }
        return parts.count - 1
    }

    func content(_ p: Double) -> some View {
        let part = Self.parts[Self.index(at: p)]
        return VStack(alignment: .leading, spacing: Space.l) {
            DemoBar(window: part.window, call: part.call)
            HStack(spacing: Space.s) {
                RingView(ring(part.call), color: tint(part.call)).frame(width: 40, height: 40)
                    .id(Self.index(at: p)).transition(.opacity)
                VStack(alignment: .leading, spacing: 1) {
                    Text(part.title).font(Tokens.rounded(.title3, .semibold))
                    Text(part.detail).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                }
                Spacer(minLength: 0)
                if done {
                    Button { done = false; started = Date() } label: { Image(systemName: "arrow.counterclockwise").font(Tokens.symbol(12, .semibold)).hitTarget() }
                        .buttonStyle(.plain).foregroundStyle(Tokens.ink2).help("Play again").accessibilityLabel("Play the example again")
                }
            }
            .animation(Motion.out(0.2), value: Self.index(at: p))
            band(p)
        }
    }

    func band(_ p: Double) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Tokens.radiusTiny).strokeBorder(Tokens.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    ForEach(Array(Self.parts.enumerated()), id: \.offset) { i, part in
                        let from = Self.parts[..<i].reduce(0) { $0 + $1.share }
                        let shown = min(1, max(0, (p - from) / part.share))
                        if shown > 0 {
                            block(part.call, height: 32).frame(width: max(3, (part.share * w - 3) * shown), height: 32).offset(x: from * w)
                        }
                    }
                }
            }
            .frame(height: 32)
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(Self.parts.enumerated()), id: \.offset) { i, part in
                        let from = Self.parts[..<i].reduce(0) { $0 + $1.share }
                        Text(part.window).font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2).lineLimit(1)
                            .frame(width: part.share * g.size.width - 4, alignment: .leading).offset(x: from * g.size.width)
                            .opacity(p > from ? 1 : 0)
                    }
                }
            }
            .frame(height: 14)
        }
    }

    /// The same marks as Today's band: solid green on task, a dashed outline when not sure, a lower amber block off topic.
    @ViewBuilder func block(_ call: Reading.Call, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusTiny, style: .continuous)
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            switch call {
            case .on: shape.fill(Tokens.accentSoft).overlay { shape.strokeBorder(Tokens.accent.opacity(0.35)) }.frame(height: height)
            case .unsure: shape.fill(Tokens.window2).overlay { shape.strokeBorder(Tokens.ink2, style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }.frame(height: height)
            case .off: shape.fill(Tokens.slipSoft).overlay { shape.strokeBorder(Tokens.slip) }.frame(height: height * 0.62)
            }
        }
    }

    func ring(_ call: Reading.Call) -> RingState { switch call { case .on: return .on; case .unsure: return .unsure; case .off: return .drift } }
    func tint(_ call: Reading.Call) -> Color { switch call { case .on: return Tokens.accent; case .unsure: return Tokens.ink2; case .off: return Tokens.slip } }
}

/// Today's reading bar, for the example: Focus, the window it is reading, and its three checks with the call as the last dot.
struct DemoBar: View {
    var window: String
    var call: Reading.Call
    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "sparkles").font(Tokens.symbol(13, .semibold)).foregroundStyle(Tokens.accent)
            Text("Focus").font(Tokens.text(.body, .semibold))
            Text("reading \(window)").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).lineLimit(1)
            Spacer(minLength: Space.s)
            HStack(spacing: 3) {
                Circle().fill(Tokens.accent).frame(width: 7, height: 7)
                Capsule().fill(Tokens.track).frame(width: 9, height: 1.5)
                Circle().fill(Tokens.accent).frame(width: 7, height: 7)
                Capsule().fill(Tokens.track).frame(width: 9, height: 1.5)
                switch call {
                case .on: Circle().fill(Tokens.accent).frame(width: 7, height: 7)
                case .unsure: Circle().strokeBorder(Tokens.ink2, style: StrokeStyle(lineWidth: 1.5, dash: [1.6, 1.6])).frame(width: 8, height: 8)
                case .off: Circle().fill(Tokens.slip).frame(width: 7, height: 7)
                }
            }
        }
        .padding(.horizontal, Space.s).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
        .overlay { RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).strokeBorder(Tokens.line) }
    }
}

/// Where Focus lives during a session: its ring in the menu bar, and the panel a click opens, with the task you are typing.
struct MenuBarPicture: View {
    var task: String
    var minutes: Int?
    var body: some View {
        VStack(alignment: .ringMiddle, spacing: 6) {
            // A strip of the menu bar: Focus's ring, then a few of the system's own items.
            HStack(spacing: Space.m) {
                Spacer()
                RingView(.on, color: Tokens.ink).frame(width: 18, height: 18)
                    .padding(.horizontal, 6).frame(height: 22).background(RoundedRectangle(cornerRadius: Tokens.radiusTiny).fill(Tokens.control))
                    .alignmentGuide(.ringMiddle) { $0[HorizontalAlignment.center] }
                Image(systemName: "magnifyingglass"); Image(systemName: "switch.2"); Image(systemName: "wifi"); Image(systemName: "battery.75percent")
                Text("9:41").monospacedDigit()
            }
            .font(Tokens.text(.body, .medium)).foregroundStyle(Tokens.ink)
            .padding(.horizontal, Space.s).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous).fill(Tokens.well))
            // The panel under the ring, as the menu bar shows it during a session.
            HStack(spacing: 10) {
                RingView(.on, color: Tokens.accent).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(task.isEmpty ? "Your task" : task).font(Tokens.rounded(.callout, .semibold)).foregroundStyle(task.isEmpty ? Tokens.ink2 : Tokens.ink).lineLimit(1)
                    Text("On task \u{00B7} \(minutes == nil ? "Open" : "Timed") session").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                }
                Spacer(minLength: Space.s)
                Text(minutes.map { "\($0):00" } ?? "0:00").font(Tokens.rounded(.callout, .semibold)).monospacedDigit()
            }
            .padding(10).frame(width: 280)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.float))
            .overlay { RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).strokeBorder(Tokens.floatEdge) }
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            .alignmentGuide(.ringMiddle) { $0[HorizontalAlignment.center] }
            .animation(Motion.out(0.2), value: task.isEmpty)
        }
        .accessibilityElement()
        .accessibilityLabel("Focus's ring in the menu bar opens a panel with your task and its clock.")
    }
}

/// What Accessibility lets Focus read: a window's title bar, and Focus's reading bar taking the app, the title and the address from it.
struct AccessPicture: View {
    var allowed: Bool
    var body: some View {
        VStack(spacing: Space.s) {
            // A window, drawn small: the traffic lights, its title, and a few lines of a page.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(Tokens.track).frame(width: 9, height: 9) }
                    Spacer()
                    Text("Chapter 5 exercises.pdf").font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink)
                    Spacer()
                    Color.clear.frame(width: 39, height: 9)
                }
                .padding(.horizontal, Space.s).frame(height: 28)
                .background(Tokens.well)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([0.92, 0.78, 0.86], id: \.self) { f in Capsule().fill(Tokens.control).frame(height: 6).frame(maxWidth: .infinity, alignment: .leading).scaleEffect(x: f, anchor: .leading) }
                }
                .padding(Space.s)
            }
            .background(Tokens.window2)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous).strokeBorder(Tokens.line) }
            .frame(width: 330)
            Image(systemName: "arrow.down").font(Tokens.symbol(12, .semibold)).foregroundStyle(Tokens.ink2)
            // Focus's own reading bar, as Today shows it.
            HStack(spacing: Space.xs) {
                Image(systemName: "sparkles").font(Tokens.symbol(13, .semibold)).foregroundStyle(Tokens.accent)
                Text("Focus").font(Tokens.text(.body, .semibold))
                Text(allowed ? "reads Preview: title and page" : "sees only the app").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).lineLimit(1)
                Spacer(minLength: Space.s)
                HStack(spacing: 3) {
                    Circle().fill(Tokens.accent).frame(width: 7, height: 7)
                    Capsule().fill(Tokens.track).frame(width: 9, height: 1.5)
                    Circle().fill(allowed ? Tokens.accent : Tokens.track).frame(width: 7, height: 7)
                    Capsule().fill(Tokens.track).frame(width: 9, height: 1.5)
                    Circle().fill(allowed ? Tokens.accent : Tokens.track).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, Space.s).frame(width: 330, height: 36)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
            .overlay { RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).strokeBorder(Tokens.line) }
            .animation(Motion.out(0.24), value: allowed)
        }
        .accessibilityElement()
        .accessibilityLabel(allowed ? "Focus can read the app, the window title and the page." : "Focus can see only which app is in front.")
    }
}

/// The welcome has no toolbar of its own, so the window's title bar stays empty and blends into the page.
struct PlainTitleBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.toolbar(removing: .title).toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

/// For the snapshot tool: the welcome at a given step, with the access step's waiting line or a name already typed.
public enum WelcomePreview {
    @MainActor public static func view(_ c: SessionController, step: Int, asked: Bool = false, task: String = "") -> some View {
        WelcomeView(c: c, step: step, asked: asked, task: task)
    }
}

private extension HorizontalAlignment {
    /// The middle of Focus's ring in the menu bar picture, so the panel hangs from it.
    enum RingMiddle: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d[HorizontalAlignment.center] } }
    static let ringMiddle = HorizontalAlignment(RingMiddle.self)
}
