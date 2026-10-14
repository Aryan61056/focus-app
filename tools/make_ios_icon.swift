import AppKit
// Draws the iPhone app icon: the same Focus ring and deep green as the Mac icon (tools/make_icon.swift), but full-bleed,
// because iOS rounds the corners itself. Usage: make_ios_icon <out.png>
let s: CGFloat = 1024
let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
    NSGradient(colors: [NSColor(red: 0.13, green: 0.36, blue: 0.27, alpha: 1), NSColor(red: 0.07, green: 0.21, blue: 0.16, alpha: 1)])!.draw(in: r, angle: -90)
    let ring = NSBezierPath(ovalIn: r.insetBy(dx: s * 0.27, dy: s * 0.27))
    ring.lineWidth = s * 0.085
    NSColor(red: 0.62, green: 0.93, blue: 0.76, alpha: 1).setStroke(); ring.stroke()
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
// An opaque PNG: iOS rejects icons with an alpha channel.
let opaque = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: opaque)
rep.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try! opaque.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
