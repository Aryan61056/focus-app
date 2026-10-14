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

private extension Comparable { func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) } }
