import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
// Draws the iPhone app icon: the Mac icon's Focus ring on its deep green, but full-bleed (iOS rounds the corners itself).
// Writes icon.png, icon-dark.png and icon-tinted.png (1024 px) into the folder given. Usage: make_ios_icon <AppIcon.appiconset>
let out = CommandLine.arguments[1]
let S = 1024
func render(top: [CGFloat], bottom: [CGFloat], ring: [CGFloat], glow: Bool, name: String) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let rect = CGRect(x: 0, y: 0, width: S, height: S)
    let g = CGGradient(colorsSpace: cs, colors: [CGColor(red: top[0], green: top[1], blue: top[2], alpha: 1), CGColor(red: bottom[0], green: bottom[1], blue: bottom[2], alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(S)), end: CGPoint(x: 0, y: 0), options: [])
    let c = CGPoint(x: CGFloat(S) / 2, y: CGFloat(S) / 2)
    if glow {
        let halo = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.62, green: 0.93, blue: 0.76, alpha: 0.22), CGColor(red: 0.62, green: 0.93, blue: 0.76, alpha: 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(halo, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(S) * 0.5, options: [])
    }
    // The halftone idea, kept very quiet: a few concentric rings of dots fading out from the ring.
    let ringR = CGFloat(S) * (0.5 - 0.27) - CGFloat(S) * 0.085 / 2 + CGFloat(S) * 0.0
    for (i, r) in stride(from: ringR + CGFloat(S) * 0.085 / 2 + 36, to: CGFloat(S) * 0.7, by: 44).enumerated() {
        let n = Int(2 * .pi * r / 30)
        for k in 0..<n {
            let a = CGFloat(k) / CGFloat(n) * 2 * .pi + CGFloat(i) * 0.3
            let d = max(0, 5.5 - CGFloat(i) * 0.9)
            if d < 0.8 { continue }
            ctx.setFillColor(CGColor(red: ring[0], green: ring[1], blue: ring[2], alpha: 0.28 - CGFloat(i) * 0.04))
            ctx.fillEllipse(in: CGRect(x: c.x + cos(a) * r - d, y: c.y + sin(a) * r - d, width: d * 2, height: d * 2))
        }
    }
    ctx.setStrokeColor(CGColor(red: ring[0], green: ring[1], blue: ring[2], alpha: 1))
    ctx.setLineWidth(CGFloat(S) * 0.085)
    ctx.strokeEllipse(in: rect.insetBy(dx: CGFloat(S) * 0.27, dy: CGFloat(S) * 0.27))
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(out)/\(name)") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
}
render(top: [0.13, 0.36, 0.27], bottom: [0.06, 0.19, 0.14], ring: [0.62, 0.93, 0.76], glow: true, name: "icon.png")
render(top: [0.07, 0.17, 0.12], bottom: [0.02, 0.07, 0.05], ring: [0.62, 0.93, 0.76], glow: true, name: "icon-dark.png")
render(top: [0, 0, 0], bottom: [0, 0, 0], ring: [1, 1, 1], glow: false, name: "icon-tinted.png")
