import CoreGraphics
import Foundation
for _ in 0..<26 {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where (w[kCGWindowLayer as String] as? Int) == 25 && (w[kCGWindowOwnerName as String] as? String) == "Focus" {
        if let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Height"] ?? 0) < 400 && (b["Width"] ?? 0) > 100 { print(String(format: "%.1f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)), b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!) }
    }
    Thread.sleep(forTimeInterval: 0.5)
}
