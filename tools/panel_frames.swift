import CoreGraphics
import Foundation
// panel_frames [pid]: frames of Focus's notch-level windows, every 0.5 s. With a pid, only that process (so an installed copy is not counted).
let pid = CommandLine.arguments.dropFirst().first.flatMap { Int($0) }
for _ in 0..<26 {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where (w[kCGWindowLayer as String] as? Int) == 25 && (w[kCGWindowOwnerName as String] as? String) == "Focus" && (pid == nil || (w[kCGWindowOwnerPID as String] as? Int) == pid) {
        if let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Height"] ?? 0) < 400 && (b["Width"] ?? 0) > 100 { print(String(format: "%.1f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)), b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!) }
    }
    Thread.sleep(forTimeInterval: 0.5)
}
