import AppKit
import FocusSense

// focus-sense-check: prints whether Accessibility is allowed and the frontmost app's NAME only.
// It deliberately never prints a window title or address, so running it cannot leak what is on screen.
let source = AXWindowSource()
print("accessibility allowed: \(source.isTrusted)")
if let app = NSWorkspace.shared.frontmostApplication { print("frontmost app: \(app.localizedName ?? "unknown")") }
