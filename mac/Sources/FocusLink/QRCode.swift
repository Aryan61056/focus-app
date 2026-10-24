import AppKit
import CoreImage.CIFilterBuiltins

/// Draws a QR code for a string. Drawn straight to the screen: never encoded as an image file or put on the pasteboard.
enum QRCode {
    static func image(for text: String, points: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let out = filter.outputImage else { return nil }
        let scale = (points * 2 / out.extent.width).rounded(.down).clamped(1, 20)   // whole pixels per module keeps the edges sharp
        let big = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: big)
        let image = NSImage(size: NSSize(width: points, height: points))
        rep.size = image.size
        image.addRepresentation(rep)
        return image
    }
}

extension QRCode {
    /// The code's modules, row 0 at the top, true for dark. Whatever quiet zone the generator adds is cropped away, so the matrix starts
    /// at the first finder pattern. Computed in memory, never encoded to a file.
    static func modules(for text: String) -> [[Bool]]? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let out = filter.outputImage else { return nil }
        let w = Int(out.extent.width), h = Int(out.extent.height)
        guard w > 0, h > 0 else { return nil }
        var px = [UInt8](repeating: 255, count: w * h)
        CIContext(options: [.useSoftwareRenderer: true]).render(out, toBitmap: &px, rowBytes: w, bounds: out.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h { for x in 0..<w where px[y * w + x] < 128 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard maxX >= minX, maxX - minX == maxY - minY else { return nil }
        return (minY...maxY).map { y in (minX...maxX).map { x in px[y * w + x] < 128 } }
    }
}

private extension Comparable { func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) } }
