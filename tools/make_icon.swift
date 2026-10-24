import AppKit
// Draws the app icon (the Hushd ring on a deep green rounded square) into an .iconset folder. Usage: make_icon <out.iconset>
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
        let inset = s * 0.06
        let tile = NSBezierPath(roundedRect: r.insetBy(dx: inset, dy: inset), xRadius: s * 0.22, yRadius: s * 0.22)
        NSGradient(colors: [NSColor(red: 0.13, green: 0.36, blue: 0.27, alpha: 1), NSColor(red: 0.07, green: 0.21, blue: 0.16, alpha: 1)])!.draw(in: tile, angle: -90)
        let ring = NSBezierPath(ovalIn: r.insetBy(dx: s * 0.27, dy: s * 0.27))
        ring.lineWidth = s * 0.085
        NSColor(red: 0.62, green: 0.93, blue: 0.76, alpha: 1).setStroke(); ring.stroke()
        return true
    }
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                   ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
