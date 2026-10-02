import AppKit
let scr = NSScreen.screens.first!

let x = scr.frame.midX, yTop = 10.0   // CG coords: origin top-left
func move(_ x: Double, _ y: Double) {
    CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
    let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
    e?.post(tap: .cghidEventTap)
}
move(x - 300, 300); Thread.sleep(forTimeInterval: 0.5)
for _ in 0..<3 {
  for dy in stride(from: 300.0, through: yTop, by: -40) { move(x, dy); Thread.sleep(forTimeInterval: 0.05) }
  Thread.sleep(forTimeInterval: 1.0)
  move(x - 300, 300); Thread.sleep(forTimeInterval: 1.0)
}
