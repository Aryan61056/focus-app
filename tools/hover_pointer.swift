import AppKit
// Moves the real pointer onto the notch/pill panel of the running focus-app (found by its window: layer 25, a few dozen points tall), rests there,
// then away, three times. Usage: hover_pointer [seconds-to-rest-on-it]. Falls back to the top centre of the first screen if there is no panel.
let rest = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 1.0 : 1.0
func panelCenter() -> CGPoint? {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where (w[kCGWindowLayer as String] as? Int) == 25 && (w[kCGWindowOwnerName as String] as? String) == "Focus" {
        if let b = w[kCGWindowBounds as String] as? [String: CGFloat], let x = b["X"], let y = b["Y"], let wd = b["Width"], let h = b["Height"], h < 200, wd > 100 {
            return CGPoint(x: x + wd / 2, y: y + h / 2)
        }
    }
    return nil
}
let target = panelCenter() ?? CGPoint(x: NSScreen.screens[0].frame.midX, y: 10)
func move(_ p: CGPoint) {
    CGWarpMouseCursorPosition(p)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
let away = CGPoint(x: target.x - 400, y: target.y + 300)
move(away); Thread.sleep(forTimeInterval: 0.5)
for _ in 0..<3 {
    for k in stride(from: 8, through: 0, by: -1) { move(CGPoint(x: target.x, y: target.y + CGFloat(k) * 30)); Thread.sleep(forTimeInterval: 0.05) }
    Thread.sleep(forTimeInterval: rest)
    move(away); Thread.sleep(forTimeInterval: 1.0)
}
