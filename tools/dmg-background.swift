import AppKit

// Draws the DMG window background at 1x and 2x for Hushd. Usage: dmg-background <out-dir> [--notarized]
// The window is 660x400 pt; the app icon sits at (180, 190) and Applications at (480, 190), measured from the top-left.
// Same look as the welcome: deep green ground, soft green light, glass tiles behind the two icons, one dotted arrow.
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let notarized = CommandLine.arguments.contains("--notarized")
let size = NSSize(width: 660, height: 400)
let green = NSColor(srgbRed: 0x78 / 255, green: 0xD5 / 255, blue: 0x9D / 255, alpha: 1)

func render(scale: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bounds = NSRect(origin: .zero, size: size)

    NSColor(srgbRed: 0x0F / 255, green: 0x16 / 255, blue: 0x12 / 255, alpha: 1).setFill(); bounds.fill()
    NSGradient(colors: [green.withAlphaComponent(0.22), .clear])!
        .draw(fromCenter: NSPoint(x: 330, y: 410), radius: 0, toCenter: NSPoint(x: 330, y: 410), radius: 400, options: [])
    NSGradient(colors: [green.withAlphaComponent(0.10), .clear])!
        .draw(fromCenter: NSPoint(x: 620, y: -10), radius: 0, toCenter: NSPoint(x: 620, y: -10), radius: 340, options: [])

    func text(_ s: String, size pt: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat) {
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: pt, weight: weight), .foregroundColor: NSColor.white.withAlphaComponent(alpha), .paragraphStyle: para,
        ]
        NSAttributedString(string: s, attributes: attrs).draw(in: NSRect(x: 0, y: y, width: size.width, height: pt * 1.5))
    }
    // Hushd's ring, small, above the title.
    let ring = NSBezierPath(ovalIn: NSRect(x: 330 - 14, y: 350, width: 28, height: 28))
    ring.lineWidth = 4; green.setStroke(); ring.stroke()
    text("Drag Hushd into Applications", size: 24, weight: .semibold, alpha: 0.95, y: 308)
    text("Then open it and enter your key.", size: 13.5, weight: .regular, alpha: 0.55, y: 280)

    // Glass tiles behind the two icons: a faint fill and a hairline edge, lit from the top.
    for x in [180.0, 480.0] {
        let tile = NSBezierPath(roundedRect: NSRect(x: x - 82, y: 108, width: 164, height: 176), xRadius: 30, yRadius: 30)
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.09), NSColor.white.withAlphaComponent(0.03)])!.draw(in: tile, angle: -90)
        NSColor.white.withAlphaComponent(0.12).setStroke(); tile.lineWidth = 1; tile.stroke()
    }

    // A dotted arrow between the tiles (y measured from the bottom: 400 - 190 = 210).
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 276, y: 210))
    arrow.curve(to: NSPoint(x: 388, y: 210), controlPoint1: NSPoint(x: 305, y: 236), controlPoint2: NSPoint(x: 359, y: 236))
    arrow.lineWidth = 3.2; arrow.lineCapStyle = .round
    arrow.setLineDash([1, 9], count: 2, phase: 0)
    green.withAlphaComponent(0.9).setStroke(); arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 376, y: 224)); head.line(to: NSPoint(x: 394, y: 207)); head.line(to: NSPoint(x: 373, y: 197))
    head.lineWidth = 3.4; head.lineCapStyle = .round; head.lineJoinStyle = .round
    green.setStroke(); head.stroke()

    // Finder prints icon names in black, so each name sits on a pale plate to stay readable on the dark art.
    for x in [180.0, 480.0] {
        let plate = NSBezierPath(roundedRect: NSRect(x: x - 52, y: 121, width: 104, height: 22), xRadius: 11, yRadius: 11)
        NSColor.white.withAlphaComponent(0.86).setFill(); plate.fill()
    }

    if !notarized {
        text("First time: if macOS can\u{2019}t check Hushd, open System Settings, Privacy & Security, and choose Open Anyway.", size: 11, weight: .regular, alpha: 0.42, y: 24)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
