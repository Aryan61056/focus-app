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

@MainActor func render(_ c: SessionController, _ name: String, dark: Bool, selection: AppSection = .today) {
    let view = RootView(controller: c, selection: selection).frame(width: 1240, height: 800)
        .environment(\.colorScheme, dark ? .dark : .light)
    let r = ImageRenderer(content: view)
    r.scale = 1
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { print("render failed: \(name)"); return }
    let path = "\(outDir)/\(name)-\(dark ? "dark" : "light").png"
    try? png.write(to: URL(fileURLWithPath: path)); print(path)
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

    c.windowChanged(WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1"))
    await advance(c, to: 95)
    for dark in [false, true] { render(c, "drifting", dark: dark) }
    while c.surface == nil && t < 300 { await advance(c, to: t + 1) }
    for dark in [false, true] { render(c, "nudge", dark: dark) }
    print("state:", c.presence, "surface:", String(describing: c.surface), "veil:", c.veilTarget)
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

@MainActor func screens() {
    let store = seededStore()
    let c = SessionController(judge: judge, store: store, now: { 0 })
    render(c, "today-full", dark: false, selection: .today)
    render(c, "today-full", dark: true, selection: .today)
    for (sec, name) in [(AppSection.projects, "projects"), (.history, "history"), (.review, "review"), (.insights, "insights"), (.settings, "settings")] {
        for dark in [false, true] { render(c, name, dark: dark, selection: sec) }
    }
}
await run()
screens()
