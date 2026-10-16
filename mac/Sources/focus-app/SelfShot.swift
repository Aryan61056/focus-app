import AppKit
import FocusUI
import FocusJudge

/// Developer tool, only with FOCUS_DEMO=1 and FOCUS_SELFSHOT=<folder>: after a few seconds, draws this app's own windows (the main window
/// and the notch panel, with scripted demo data) to PNG files and quits. It renders views, it does not capture the screen, so it needs no permission.
@MainActor
enum SelfShot {
    /// FOCUS_DEMO_ACTIONS="section:settings,start" runs these on the controller after 3 s (demo only), in place of clicks and keys I cannot send:
    /// section:<today|projects|history|insights|review|settings>, start (opens the start sheet), readscreen (turns screen reading on), veil (the whole-screen gray fade, 10 s).
    static func runActions(_ controller: SessionController) {
        let env = ProcessInfo.processInfo.environment
        guard env["FOCUS_DEMO"] == "1", let list = env["FOCUS_DEMO_ACTIONS"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            for a in list.split(separator: ",").map(String.init) {
                if a.hasPrefix("section:"), let s = AppSection.allCases.first(where: { $0.rawValue.lowercased() == a.dropFirst(8).lowercased() }) { controller.requestSection(s) }
                else if a.hasPrefix("example") {
                    controller.showExample()
                    let parts = a.split(separator: ":")
                    if parts.count == 2, let step = Int(parts[1]) { controller.example?.select(step) }
                }
                else if a == "stuck" { controller.assistant = ExampleAssistant(); controller.requestNextActions() }
                else if a == "park" || a == "park-long" { controller.onParkThought?() }
                else if a == "parked-all" {
                    for i in 1...12 { controller.store?.park("Synthetic thought \(i): ask about the lab materials") }
                    controller.act(.breakTime, minutes: 5)
                }
                else if a == "parked" { controller.store?.park("Ask about the synthetic lab materials"); controller.store?.park("Pick up a notebook"); controller.act(.breakTime, minutes: 5) }
                else if a == "start" { controller.requestStart() }
                else if a == "readscreen" { controller.prefs.readScreen = true }
                else if a == "veil" { controller.previewVeil() }   // the whole-screen gray, so its windows can be listed
            }
        }
    }

    static func scheduleIfRequested(after seconds: Double = 12) {
        let env = ProcessInfo.processInfo.environment
        guard env["FOCUS_DEMO"] == "1", let dir = env["FOCUS_SELFSHOT"] else { return }
        // FOCUS_SELFSHOT_APPEARANCE=light|dark renders in that appearance whatever the system uses.
        if let a = env["FOCUS_SELFSHOT_APPEARANCE"] { NSApp.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(env["FOCUS_SELFSHOT_AFTER"] ?? "") ?? seconds)) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            for (i, w) in NSApp.windows.enumerated() where w.isVisible {
                guard let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(dir)/window-\(i)-\(Int(w.frame.width))x\(Int(w.frame.height)).png"))
                }
            }
            NSApp.terminate(nil)
        }
    }
}

private struct ExampleAssistant: Assistant {
    func sharpen(task: String, context: String) async -> Sharpened? { nil }
    func recap(facts: String) async -> Recap? { nil }
    func answer(question: String, facts: String) async -> String? { nil }
    func nextActions(task: String, context: String) async -> [String]? {
        ["Choose u and dv for the first calculus integral.", "Differentiate your chosen calculus expression.", "Write the calculus rule beside your working."]
    }
}
