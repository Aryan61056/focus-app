import AppKit

/// Developer tool, only with FOCUS_DEMO=1 and FOCUS_SELFSHOT=<folder>: after a few seconds, draws this app's own windows (the main window
/// and the notch panel, with scripted demo data) to PNG files and quits. It renders views, it does not capture the screen, so it needs no permission.
@MainActor
enum SelfShot {
    static func scheduleIfRequested(after seconds: Double = 12) {
        let env = ProcessInfo.processInfo.environment
        guard env["FOCUS_DEMO"] == "1", let dir = env["FOCUS_SELFSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
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
