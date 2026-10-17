import SwiftUI
import AppKit
import FocusUI
import FocusBrain
import FocusJudge

// focus-snapshot <out dir>: renders the app's screens offscreen with a scripted judge and a fake clock.
// Nothing here reads the real screen or any real window.
SnapshotMode.on = true
let outDir = CommandLine.arguments.dropFirst().first ?? "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var t = 0.0
let judge = ScriptedJudge(readings: [
    ("youtube", .off, "A video about something unrelated to integration by parts."),
    ("Chapter", .on, "A page of calculus exercises, which is the work Calc homework is about."),
    ("Messages", .unsure, "A chat. It could be about the homework or something else, so Focus is leaving it alone."),
    ("Notes", .on, "Your own notes for the calculus homework, which is the work itself."),
])

@MainActor func advance(_ c: SessionController, to target: Double) async {
    while t < target { t += 1; c.tick(); await c.waitForJudgments() }
}

@MainActor func render(_ c: SessionController, _ name: String, dark: Bool, selection: AppSection = .today, height: CGFloat = 800) {
    // The screens, not the welcome a new store would open on (the welcome has its own shots under --popups).
    c.prefs.welcomeSeen = true
    // --window: the window server draws it, so scroll views, fields and glass appear as they do in the app.
    if CommandLine.arguments.contains("--window") {
        WindowShot.shot(RootView(controller: c, selection: selection).frame(width: 1240, height: height), size: CGSize(width: 1240, height: height), name: name, dark: dark, dir: outDir)
        return
    }
    let view = RootView(controller: c, selection: selection).frame(width: 1240, height: height)
        .environment(\.colorScheme, dark ? .dark : .light)
    let r = ImageRenderer(content: view)
    r.scale = 1
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { print("render failed: \(name)"); return }
    let path = "\(outDir)/\(name)-\(dark ? "dark" : "light").png"
    try? png.write(to: URL(fileURLWithPath: path)); print(path)
}

@MainActor func shot(_ name: String, _ c: SessionController) {
    let v = NotchView(controller: c, notchWidth: 200, notchHeight: 32, forced: .nudge)
    let wall = ZStack(alignment: .top) { Color(red: 0.15, green: 0.22, blue: 0.3); v }.frame(width: 460, height: 150)
    let r = ImageRenderer(content: wall); r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

@MainActor func run() async {
    let idle = SessionController(judge: judge, now: { t })
    for dark in [false, true] { render(idle, "idle", dark: dark) }

    t = 0
    let c = SessionController(judge: judge, now: { t })
    c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
    c.begin(task: "Calc homework", preset: .standard, shadow: false)
    await advance(c, to: 12)
    c.windowChanged(WindowSnapshot(app: "Messages", title: "Messages, a conversation"))
    await advance(c, to: 20)
    c.windowChanged(WindowSnapshot(app: "Preview", title: "Chapter 5 exercises.pdf, page 12"))
    await advance(c, to: 30)
    for dark in [false, true] { render(c, "on-task", dark: dark) }
    // The menu bar popover, which holds every quick function (drawn here; the real one is a system menu bar window).
    for dark in [false, true] {
        png(MenuBarContent(controller: c, openApp: {}).background(Tokens.window).environment(\.colorScheme, dark ? .dark : .light), "menubar-popover-\(dark ? "dark" : "light")")
    }

    // Live preview card with a synthetic picture (drawn here, not a capture of any screen).
    let pw = 720, ph = 450
    if let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
        ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
        ctx.setFillColor(CGColor(red: 0.8, green: 0.82, blue: 0.8, alpha: 1))
        for i in 0..<9 { ctx.fill(CGRect(x: 60, y: ph - 90 - i * 38, width: i % 3 == 2 ? 360 : 600, height: 14)) }
        if let img = ctx.makeImage() {
            c.prefs.readScreen = true; c.setPreview(img, app: "Preview", text: "Chapter 5 exercises\nProblem 4. Integrate x e^x dx using integration by parts.\nProblem 5. Evaluate the integral of ln x dx.")
            for dark in [false, true] { render(c, "on-task-preview", dark: dark) }
            c.prefs.readScreen = false; c.clearPreview()
        }
    }

    c.windowChanged(WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1"))
    await advance(c, to: 95)
    for dark in [false, true] { render(c, "drifting", dark: dark) }
    while c.surface == nil && t < 300 { await advance(c, to: t + 1) }
    for dark in [false, true] { render(c, "nudge", dark: dark) }
    notchShots(c)
    // Ignored warning: the check-in after about 40 s, then the pause screen after about 100 s.
    let warned = t
    c.act(.dismiss)
    await advance(c, to: warned + 45)
    render(c, "checkin", dark: false)
    shot("notch-checkin", c)
    await advance(c, to: warned + 105)
    for dark in [false, true] { render(c, "gate", dark: dark) }
    print("state:", c.presence, "surface:", String(describing: c.surface), "veil:", c.veilTarget)
    await cueShots()
}

/// A stand-in for the window you drifted into: a title bar and some gray lines, so the banner can be seen on something. Drawn here, not captured.
struct FakeWindow<Over: View>: View {
    var dark: Bool
    @ViewBuilder var over: Over
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.32, green: 0.42, blue: 0.55), Color(red: 0.2, green: 0.28, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                Rectangle().fill(dark ? Color(white: 0.2) : Color(white: 0.93)).frame(height: 34)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(dark ? Color(white: 0.13) : Color.white)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(0..<9, id: \.self) { i in RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.25)).frame(width: i % 3 == 2 ? 280 : 480, height: 12) }
                    }.padding(28).padding(.top, 36)
                }
            }
            .frame(width: 640, height: 300).clipShape(RoundedRectangle(cornerRadius: 10)).shadow(radius: 12, y: 6).padding(.top, 26)
            over.padding(.top, 26 + 34)
        }
    }
}

@MainActor func png<V: View>(_ v: V, _ name: String, scale: CGFloat = 2) {
    let r = ImageRenderer(content: v); r.scale = scale
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { print("render failed: \(name)"); return }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png")); print("\(outDir)/\(name).png")
}

@MainActor func cueShots() async {
    t = 0
    let c = SessionController(judge: judge, store: DataStore(), now: { t })
    c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
    c.begin(task: "Calc homework", preset: .standard, shadow: false)
    await advance(c, to: 20)
    c.windowChanged(WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1"))
    while c.presence.state != "interrupted" && t < 300 { await advance(c, to: t + 1) }
    for dark in [false, true] {
        png(FakeWindow(dark: dark) { CuePreview.banner(c, .reminder) }.frame(width: 760, height: 380).environment(\.colorScheme, dark ? .dark : .light), "banner-reminder-\(dark ? "dark" : "light")")
        png(FakeWindow(dark: dark) { CuePreview.banner(c, .early) }.frame(width: 760, height: 380).environment(\.colorScheme, dark ? .dark : .light), "banner-early-\(dark ? "dark" : "light")")
        
    }
    // The shield, over a stand-in for the screen (the real one blurs what is behind it).
    let shields: [(String, Shield.Kind, Double, Bool, Bool, String?, Int)] = [
        ("shield-pause-waiting", .pause, 30, false, false, nil, 2),
        ("shield-friction-waiting", .friction, 20, false, false, nil, 2),
        ("shield-explain-ready", .claim, 0, false, false, nil, 2),
        ("shield-asking", .claim, 0, true, false, nil, 2),
        ("shield-refused", .claim, 0, true, false, "This does not look like Calc homework. 1 try left.", 1),
        ("shield-checking", .claim, 0, true, true, nil, 2),
        ("shield-locked", .pause, 0, false, false, "Focus could not verify this. Explaining is locked for 5 minutes. Going back to the task works now.", 2),
    ]
    for (name, kind, wait, asking, checking, message, tries) in shields {
        t = 0
        let sc = SessionController(judge: judge, store: DataStore(), now: { t })
        sc.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        sc.begin(task: "Calc homework", preset: .standard, shadow: false)
        await sc.waitForJudgments()
        sc.debugShowShield(kind, wait: wait, asking: asking, checking: checking, message: message, attemptsLeft: tries)
        if name == "shield-locked" { sc.debugLock() }
        for dark in [false, true] {
            png(FakeWindow(dark: dark) { EmptyView() }.overlay { CuePreview.shield(sc) }.frame(width: 760, height: 560).environment(\.colorScheme, dark ? .dark : .light), "\(name)-\(dark ? "dark" : "light")")
        }
    }
    // Scheduled prompts: a check-in, and a break after a block of work.
    for (name, rhythm) in [("rhythm-checkin", Rhythm.checkIns), ("rhythm-break", .pomodoro)] {
        t = 0
        let r = SessionController(judge: judge, store: DataStore(), now: { t })
        r.prefs.rhythm = rhythm
        r.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        r.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(r, to: 25 * 60 + 1)
        for dark in [false, true] {
            png(ZStack { Tokens.window; CuePreview.rhythm(r) }.frame(width: 420, height: 300).environment(\.colorScheme, dark ? .dark : .light), "\(name)-\(dark ? "dark" : "light")")
        }
        if rhythm == .pomodoro { notchRhythm(r) }
    }
    // Menu bar ring with its cues.
    let ring = HStack(spacing: 18) {
        ForEach([("plain", nil as NSColor?), ("heads-up / prompt", RingImage.warm), ("away, bright", RingImage.warm), ("away, dim", RingImage.warm.withAlphaComponent(0.35))], id: \.0) { item in
            VStack(spacing: 6) {
                Image(nsImage: RingImage.make(.drift, size: 36, tint: item.1)).background(Color(white: item.0 == "plain" ? 0.12 : 0.12))
                Text(item.0).font(.system(size: 10)).foregroundStyle(.white)
            }
        }
    }.padding(20).background(Color(white: 0.12))
    png(ring, "menubar-cues")
}

@MainActor func notchRhythm(_ c: SessionController) {
    let v = NotchView(controller: c, notchWidth: 200, notchHeight: 32, forced: .nudge)
    png(ZStack(alignment: .top) { Color(red: 0.15, green: 0.22, blue: 0.3); v }.frame(width: 460, height: 150), "notch-rhythm")
}

@MainActor func seededStore() -> DataStore {
    let store = DataStore()
    var calc = store.addProject(name: "Calc homework")
    calc.context = "Calculus II, chapter 5: integration by parts. The textbook is the PDF in Documents."
    calc.nextStep = "Check problem 4"
    calc.profile.alwaysAllowApps = ["Preview", "Notes", "Calculator"]
    calc.profile.alwaysAllowDomains = ["khanacademy.org", "desmos.com", "wolframalpha.com"]
    calc.profile.linkedPaths = ["~/Documents/Calc II"]
    calc.profile.alwaysOffDomains = ["youtube.com/shorts"]
    store.update(calc)
    let essay = store.addProject(name: "Essay on sleep and memory")
    _ = store.addProject(name: "Lab report on pendulums")
    func rec(_ p: Project, _ daysAgo: Double, _ minutes: Double, _ segs: [(TimelineSegment.Kind, Double)], drifts: Int, note: String = "") {
        let start = Date(timeIntervalSince1970: 1_790_000_000 - daysAgo * 86400)
        let segments = segs.map { TimelineSegment($0.0, $0.1 * 60) }
        let off = segs.filter { $0.0 == .off }.reduce(0) { $0 + $1.1 } * 60, un = segs.filter { $0.0 == .unsure }.reduce(0) { $0 + $1.1 } * 60
        var r = SessionRecord(projectId: p.id, task: p.name, timed: false, start: start, end: start.addingTimeInterval(minutes * 60), activeSeconds: minutes * 60,
                              offTopicSeconds: off, unsureSeconds: un, drifts: drifts, interrupts: 0, refusals: 0, shadowMarks: 0, segments: segments)
        r.note = note
        var rs = ReadStats(); rs.model = Int(minutes) / 2; rs.rule = Int(minutes) / 8; rs.offTask = drifts * 2; rs.unsure = Int(minutes) / 12; rs.onTask = rs.model + rs.rule - rs.offTask - rs.unsure
        r.reads = rs
        store.record(r)
    }
    // Sessions earlier today, so Today's day track and week bars have something to show.
    let cal = Calendar.current
    func today(_ hour: Int, _ minutes: Double, _ segs: [(TimelineSegment.Kind, Double)], drifts: Int) {
        let start = cal.date(bySettingHour: hour, minute: 5, second: 0, of: Date())!
        let off = segs.filter { $0.0 == .off }.reduce(0) { $0 + $1.1 } * 60, un = segs.filter { $0.0 == .unsure }.reduce(0) { $0 + $1.1 } * 60
        store.record(SessionRecord(projectId: calc.id, task: calc.name, timed: false, start: start, end: start.addingTimeInterval(minutes * 60), activeSeconds: minutes * 60,
                                   offTopicSeconds: off, unsureSeconds: un, drifts: drifts, interrupts: 0, refusals: 0, shadowMarks: 0, segments: segs.map { TimelineSegment($0.0, $0.1 * 60) }))
    }
    today(9, 50, [(.on, 22), (.unsure, 2), (.on, 24), (.off, 2)], drifts: 1)
    today(11, 40, [(.on, 18), (.off, 1), (.on, 21)], drifts: 1)
    for d in 1...5 { let h = [2.0, 3.2, 1.4, 2.6, 0.8][d - 1]; let start = cal.date(byAdding: .day, value: -d, to: Date())!
        store.record(SessionRecord(projectId: calc.id, task: calc.name, timed: false, start: start, end: start.addingTimeInterval(h * 3600), activeSeconds: h * 3600, offTopicSeconds: 0, unsureSeconds: 0, drifts: 0, interrupts: 0, refusals: 0, shadowMarks: 0, segments: [TimelineSegment(.on, h * 3600)])) }
    rec(essay, 3, 95, [(.on, 30), (.off, 3), (.on, 40), (.off, 2), (.on, 20)], drifts: 2, note: "Added three citations.")
    rec(calc, 2, 72, [(.on, 30), (.off, 1), (.on, 41)], drifts: 1)
    rec(calc, 1, 44, [(.on, 25), (.off, 1), (.on, 18)], drifts: 1, note: "Problems 1 to 3 done. Stuck on 4.")
    store.addReview(ReviewMoment(sessionId: nil, projectId: calc.id, at: Date(timeIntervalSince1970: 1_789_950_000), windowKey: "safari|youtube.com/watch", siteKey: "safari|youtube.com",
                                 reason: "A video about something unrelated to integration by parts, and it ran for over a minute."))
    store.addReview(ReviewMoment(sessionId: nil, projectId: essay.id, at: Date(timeIntervalSince1970: 1_789_900_000), windowKey: "safari|nytimes.com/a", siteKey: "safari|nytimes.com",
                                 reason: "A news article. Nothing in it connects to sleep and memory, so Focus marked it."))
    for (i, ans) in ["right", "right", "right", "fine"].enumerated() {
        var m = ReviewMoment(sessionId: nil, projectId: calc.id, at: Date(timeIntervalSince1970: 1_789_800_000 + Double(i)), windowKey: "k\(i)", siteKey: "k\(i)")
        m.answer = ans; store.addReview(m)
    }
    return store
}

@MainActor func notchShots(_ c: SessionController) {
    func shot(_ name: String, _ v: NotchView, _ w: CGFloat, _ h: CGFloat) {
        let wall = ZStack(alignment: .top) { LinearGradient(colors: [Color(red: 0.2, green: 0.3, blue: 0.4), Color(red: 0.1, green: 0.15, blue: 0.2)], startPoint: .top, endPoint: .bottom); v }
            .frame(width: w, height: h)
        let r = ImageRenderer(content: wall); r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { print("render failed: \(name)"); return }
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png")); print("\(outDir)/\(name).png")
    }
    for (label, mode) in [("rest", NotchMode.rest), ("open", .open), ("nudge", .nudge)] {
        shot("notch-\(label)", NotchView(controller: c, notchWidth: 200, notchHeight: 32, forced: mode), 460, 150)
        shot("pill-\(label)", NotchView(controller: c, notchWidth: 0, notchHeight: 0, forced: mode), 460, 150)
    }
}

@MainActor func screens() {
    let store = seededStore()
    let c = SessionController(judge: judge, store: store, now: { 0 })
    render(c, "today-full", dark: false, selection: .today)
    render(c, "today-full", dark: true, selection: .today)
    for (sec, name) in [(AppSection.projects, "projects"), (.history, "history"), (.review, "review"), (.insights, "insights")] {
        for dark in [false, true] { render(c, name, dark: dark, selection: sec) }
    }
    for dark in [false, true] { render(c, "settings", dark: dark, selection: .settings, height: 3300) }
    // Late afternoon, well short of a bigger goal: Today says why Focus is firmer.
    let late = SessionController(judge: judge, store: store, now: { 0 }, date: { Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date())! })
    late.prefs.paceMatters = true; late.prefs.dailyGoalMinutes = 180
    for dark in [false, true] { render(late, "today-behind", dark: dark, selection: .today) }
}
if CommandLine.arguments.contains("--popups") { await popupShots() } else { await run(); screens() }

/// focus-snapshot <dir> --popups: every surface that appears while you drift, drawn by the window server (glass and text fields included).
@MainActor func popupShots() async {
    func session(_ preset: Preset = .standard) async -> SessionController {
        t = 0
        let c = SessionController(judge: judge, store: DataStore(), now: { t })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: preset, shadow: false)
        await advance(c, to: 20)
        return c
    }
    let wall = Color(red: 0.2, green: 0.27, blue: 0.36)
    func both<V: View>(_ name: String, _ size: CGSize, @ViewBuilder _ v: @escaping () -> V) {
        for dark in [false, true] { WindowShot.shot(v(), size: size, name: name, dark: dark, dir: outDir) }
    }
    // The welcome on a new Mac, each step, at the window's default and smallest sizes.
    let fresh = SessionController(judge: judge, store: DataStore(), now: { t })
    for (name, step, asked, typed) in [("welcome-1", 0, false, ""), ("welcome-2", 1, false, ""), ("welcome-2-waiting", 1, true, ""), ("welcome-3", 2, false, ""), ("welcome-3-typed", 2, false, "Calc homework 50")] {
        both("pop-\(name)", CGSize(width: 1240, height: 800)) { WelcomePreview.view(fresh, step: step, asked: asked, task: typed) }
    }
    both("pop-welcome-1-small", CGSize(width: 960, height: 600)) { WelcomePreview.view(fresh, step: 0) }
    both("pop-welcome-2-small", CGSize(width: 960, height: 600)) { WelcomePreview.view(fresh, step: 1, asked: true) }
    // The start sheet on a name close to an older project: the hint while typing, then the question Start asks.
    let near = SessionController(judge: judge, store: DataStore(), now: { t })
    if let store = near.store { var p = store.addProject(name: "Calc homework"); p.nextStep = "Problems 12 to 20"; store.update(p) }
    both("pop-start-near", CGSize(width: 560, height: 360)) { CuePreview.startSheet(near, typed: "calc homwork", asking: false) }
    both("pop-start-asking", CGSize(width: 560, height: 420)) { CuePreview.startSheet(near, typed: "calc homwork", asking: true) }
    // The notch on task, in every state it can be in without a nudge, at this Mac's real notch (185 x 32 pt).
    let calm = await session()
    for (name, mode, tab) in [("rest", NotchMode.rest, NotchTab.home), ("peek", .peek, .home), ("open", .open, .home), ("open-tray", .open, .tray), ("open-widgets", .open, .widgets)] {
        let m = NotchModel(); m.tab = tab
        both("pop-notch-\(name)", CGSize(width: 760, height: 240)) { ZStack(alignment: .top) { wall; NotchView(controller: calm, notchWidth: 185, notchHeight: 32, forced: mode, model: m) } }
    }
    // The menu bar panel during a session, with the reading line and the control tiles.
    both("pop-menubar", CGSize(width: 312, height: 470)) { ZStack(alignment: .top) { Tokens.card; MenuBarContent(controller: calm, openApp: {}) } }
    both("pop-pill-rest", CGSize(width: 760, height: 120)) { ZStack(alignment: .top) { wall; NotchView(controller: calm, notchWidth: 0, notchHeight: 0, forced: .rest) } }
    // Early banner at a real heads-up, so its counts are real.
    let c = await session()
    c.windowChanged(WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1"))
    while c.surface == nil && t < 300 { await advance(c, to: t + 1) }
    both("pop-nudge", CGSize(width: 760, height: 380)) { FakeWindow(dark: false) { EmptyView() }.overlay(alignment: .topTrailing) { CuePreview.nudge(c).padding(Space.l) } }
    both("pop-banner-reminder", CGSize(width: 760, height: 380)) { FakeWindow(dark: false) { CuePreview.banner(c, .reminder) } }
    both("pop-banner-early", CGSize(width: 760, height: 380)) { FakeWindow(dark: false) { CuePreview.banner(c, .early) } }
    both("pop-notch-nudge", CGSize(width: 760, height: 200)) { ZStack(alignment: .top) { wall; NotchView(controller: c, notchWidth: 185, notchHeight: 32, forced: .nudge) } }
    both("pop-pill-nudge", CGSize(width: 760, height: 200)) { ZStack(alignment: .top) { wall; NotchView(controller: c, notchWidth: 0, notchHeight: 0, forced: .nudge) } }
    let warned = t
    c.act(.dismiss)
    await advance(c, to: warned + 45)
    both("pop-banner-checkin", CGSize(width: 760, height: 380)) { FakeWindow(dark: false) { CuePreview.banner(c, .checkIn) } }
    both("pop-checkin", CGSize(width: 760, height: 380)) { FakeWindow(dark: false) { EmptyView() }.overlay(alignment: .topTrailing) { CuePreview.checkIn(c).padding(Space.l) } }
    both("pop-notch-checkin", CGSize(width: 760, height: 200)) { ZStack(alignment: .top) { wall; NotchView(controller: c, notchWidth: 185, notchHeight: 32, forced: .nudge) } }
    let shields: [(String, Shield.Kind, Bool, Bool, String?, Int, Bool)] = [
        ("pop-shield-pause", .pause, false, false, nil, 2, false),
        ("pop-shield-friction", .friction, false, false, nil, 2, false),
        ("pop-shield-claim", .claim, false, false, nil, 2, false),
        ("pop-shield-asking", .claim, true, false, nil, 2, false),
        ("pop-shield-refused", .claim, true, false, "This does not look like Calc homework. 1 try left.", 1, false),
        ("pop-shield-checking", .claim, true, true, nil, 2, false),
        ("pop-shield-locked", .pause, false, false, nil, 2, true),
    ]
    for (name, kind, asking, checking, message, tries, locked) in shields {
        let sc = await session()
        sc.debugShowShield(kind, asking: asking, checking: checking, message: message, attemptsLeft: tries)
        if locked { sc.debugLock() }
        // The real shield sits on a full-screen blur; blurring the stand-in window gets close to it.
        both(name, CGSize(width: 1000, height: 700)) { ZStack { FakeWindow(dark: false) { EmptyView() }.blur(radius: 18); CuePreview.shield(sc) } }
    }
    let hold = await session()
    hold.prefs.holdToReturn = true
    hold.debugShowShield(.pause)
    both("pop-shield-hold", CGSize(width: 1000, height: 700)) { ZStack { FakeWindow(dark: false) { EmptyView() }.blur(radius: 18); CuePreview.shield(hold) } }
    for (name, rhythm) in [("pop-rhythm-checkin", Rhythm.checkIns), ("pop-rhythm-break", .pomodoro)] {
        let r = await session()
        r.prefs.rhythm = rhythm
        await advance(r, to: 25 * 60 + 25)
        both(name, CGSize(width: 760, height: 380)) { FakeWindow(dark: false) { EmptyView() }.overlay(alignment: .topTrailing) { CuePreview.rhythm(r) } }
        both(name.replacingOccurrences(of: "pop-", with: "pop-banner-"), CGSize(width: 760, height: 380)) { FakeWindow(dark: false) { CuePreview.banner(r, .rhythm) } }
        both(name.replacingOccurrences(of: "pop-", with: "pop-notch-"), CGSize(width: 760, height: 200)) { ZStack(alignment: .top) { wall; NotchView(controller: r, notchWidth: 185, notchHeight: 32, forced: .nudge) } }
    }
}
