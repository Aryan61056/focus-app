import SwiftUI
import AppKit

/// ImageRenderer cannot draw glass, materials, text fields or scroll views, so the floating cards and the shield came out blank or with
/// a placeholder. This hosts a view in a borderless window of this process placed far off every display, lets the window server draw it,
/// and copies that one window back. No other window and no screen content is read, so it needs no permission.
@MainActor enum WindowShot {
    static var started = false
    static func start() {
        guard !started else { return }
        started = true
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
    }

    /// `backdrop` is drawn behind the view inside the same window, standing in for whatever would be under a floating panel.
    static func shot<V: View>(_ view: V, size: CGSize, name: String, dark: Bool, dir: String) {
        start()
        let w = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = true; w.hasShadow = false
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        host.frame = NSRect(origin: .zero, size: size)
        w.contentView = host
        w.orderFrontRegardless()
        // A few turns of the run loop so SwiftUI lays out and the window server has a frame to hand back.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        defer { w.orderOut(nil) }
        guard let img = image(CGWindowID(w.windowNumber)), let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else {
            print("window shot failed: \(name)"); return
        }
        let path = "\(dir)/\(name)-\(dark ? "dark" : "light").png"
        try? png.write(to: URL(fileURLWithPath: path)); print(path)
    }

    /// CGWindowListCreateImage for one window of this process, looked up at run time because it is deprecated.
    static func image(_ id: CGWindowID) -> CGImage? {
        typealias Fn = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?
        guard let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "CGWindowListCreateImage") else { return nil }
        let f = unsafeBitCast(sym, to: Fn.self)
        return f(.null, 1 << 3, id, (1 << 0) | (1 << 3))?.takeRetainedValue()
    }
}
