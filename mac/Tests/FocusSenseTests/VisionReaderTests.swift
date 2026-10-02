import XCTest
import AppKit
@testable import FocusSense

/// Runs Apple Vision on a picture drawn here (not a capture of any screen).
final class VisionReaderTests: XCTestCase {
    func testReadsWordsFromADrawnWindow() async throws {
        let size = NSSize(width: 1200, height: 400)
        let img = NSImage(size: size, flipped: false) { r in
            NSColor.white.setFill(); r.fill()
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black]
            "Chapter 5 exercises".draw(at: NSPoint(x: 40, y: 300), withAttributes: a)
            "Integrate x e^x using integration by parts".draw(at: NSPoint(x: 40, y: 200), withAttributes: a)
            return true
        }
        let cg = try XCTUnwrap(img.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let text = await VisionScreenReader().words(in: cg).lowercased()
        XCTAssertTrue(text.contains("integration"), "got: \(text)")
        XCTAssertTrue(text.contains("exercises"), "got: \(text)")
    }
}
