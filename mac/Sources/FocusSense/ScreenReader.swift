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
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([req])) != nil else { return "" }
            let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return String(lines.joined(separator: "\n").prefix(Self.maxCharacters))
        }.value
    }
}
