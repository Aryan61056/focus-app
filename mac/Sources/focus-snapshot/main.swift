import SwiftUI
import AppKit
import FocusUI
import FocusBrain
import FocusJudge

// focus-snapshot <out dir>: renders the app's screens offscreen with a scripted judge and a fake clock.
// Nothing here reads the real screen or any real window.
let outDir = CommandLine.arguments.dropFirst().first ?? "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var t = 0.0
let judge = ScriptedJudge(markers: [("youtube", .off), ("Calc", .on)])

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
    await advance(c, to: 30)
    for dark in [false, true] { render(c, "on-task", dark: dark) }

    c.windowChanged(WindowSnapshot(app: "Browser", title: "youtube clip", url: "https://youtube.com/watch?v=1"))
    await advance(c, to: 95)
    for dark in [false, true] { render(c, "drifting", dark: dark) }
    while c.surface == nil && t < 300 { await advance(c, to: t + 1) }
    for dark in [false, true] { render(c, "nudge", dark: dark) }
    print("state:", c.presence, "surface:", String(describing: c.surface), "veil:", c.veilTarget)
}
await run()
