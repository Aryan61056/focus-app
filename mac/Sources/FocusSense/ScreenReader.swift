import CoreGraphics
import Vision

/// Turns a picture of a window into the words on it. On this Mac, in memory; the picture and the words are never written anywhere.
public protocol ScreenReader: Sendable {
    func words(in image: CGImage) async -> String
}

/// Apple Vision text recognition. The S1 harness measured this path (OCR of synthetic screenshots into the same judge);
/// real windows are noisier than those, which is unmeasured.
public struct VisionScreenReader: ScreenReader {
    public static let maxCharacters = 4000
    public init() {}

    public func words(in image: CGImage) async -> String {
        await Task.detached(priority: .utility) { () -> String in
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .fast   // .accurate took 66 s on its first call in a fresh process (model load); .fast takes about 0.1 s and is enough to tell the topic
            req.usesLanguageCorrection = false
            guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([req])) != nil else { return "" }
            let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return String(lines.joined(separator: "\n").prefix(Self.maxCharacters))
        }.value
    }
}

/// A small grayscale grid of a picture, to tell whether the screen changed since the last read. In memory, a few KB, never stored.
/// Reading the words (OCR) is the costly part of screen reading, and most of the time nothing on the window has changed.
public enum PictureFingerprint {
    static let cols = 64, rows = 36

    public static func of(_ image: CGImage) -> [UInt8]? {
        var px = [UInt8](repeating: 0, count: cols * rows)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: cols,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: cols, height: rows))
            return true
        }
        return ok ? px : nil
    }

    /// True when at least a few cells of the grid moved noticeably: a cursor blink or a clock does not count, a new paragraph does.
    public static func changed(_ a: [UInt8]?, _ b: [UInt8]?) -> Bool {
        guard let a, let b, a.count == b.count else { return true }
        var cells = 0
        for i in 0..<a.count where abs(Int(a[i]) - Int(b[i])) > 8 { cells += 1; if cells >= 3 { return true } }
        return false
    }
}
