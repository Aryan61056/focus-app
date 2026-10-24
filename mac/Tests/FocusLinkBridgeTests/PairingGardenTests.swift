import XCTest
import SceneKit
import CoreImage
import Metal
import SwiftUI
@testable import FocusLink

/// The pairing garden has to end as a code a phone can read. These decode what is drawn, with a made-up address the length of a real one
/// (the length sets the code's size); nothing here uses a real pairing code, and nothing is written to disk unless GARDEN_SHOTS names a folder.
@MainActor
final class PairingGardenTests: XCTestCase {
    let fake = "focuslink://pair?c=ABCDEFGH&m=00000000-0000-4000-8000-000000000000"

    func decode(_ image: CGImage) -> String? {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return (detector?.features(in: CIImage(cgImage: image)) as? [CIQRCodeFeature])?.first?.messageString
    }

    /// The matrix read from the generator, drawn plainly: if this fails, the module reading is wrong, whatever the 3D does.
    func testModuleMatrixDecodes() throws {
        let m = try XCTUnwrap(QRCode.modules(for: fake))
        XCTAssertTrue(m.count >= 21 && m.count == m[0].count)
        XCTAssertTrue((0..<7).allSatisfy { m[0][$0] && m[6][$0] && m[$0][0] && m[$0][6] }, "the first finder square starts at the corner")
        let px = 8, quiet = 4, side = (m.count + 2 * quiet) * px
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.setFillColor(gray: 0, alpha: 1)
        for (r, row) in m.enumerated() { for (c, dark) in row.enumerated() where dark {
            ctx.fill(CGRect(x: (c + quiet) * px, y: side - (r + quiet + 1) * px, width: px, height: px))
        } }
        XCTAssertEqual(decode(ctx.makeImage()!), fake)
    }

    func render(_ garden: GardenScene, size: Int) throws -> CGImage {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "needs a GPU")
        let r = SCNRenderer(device: device, options: nil)
        r.scene = garden.scene; r.pointOfView = garden.cameraNode
        let img = r.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)
        return try XCTUnwrap(img.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    /// The end of the animation, drawn offscreen at the size it has on screen (260 pt) at 1x and 2x, reads back as the address.
    func testTheFinishedGardenScans() throws {
        let m = try XCTUnwrap(QRCode.modules(for: fake))
        let garden = GardenScene(modules: m)
        garden.apply(t: 1, time: 0, intro: 1)
        for size in [260, 520] { XCTAssertEqual(decode(try render(garden, size: size)), fake, "at \(size) px") }
    }

    /// A strip of frames, for looking at, when GARDEN_SHOTS names a folder.
    func testWritesFramesWhenAsked() throws {
        guard let dir = ProcessInfo.processInfo.environment["GARDEN_SHOTS"] else { throw XCTSkip("set GARDEN_SHOTS to a folder to write frames") }
        let garden = GardenScene(modules: try XCTUnwrap(QRCode.modules(for: fake)))
        for (i, t) in [0.0, 0.2, 0.35, 0.5, 0.65, 0.8, 1.0].enumerated() {
            garden.apply(t: t, time: 1.0, intro: 1)
            let cg = try render(garden, size: 480)
            let rep = NSBitmapImageRep(cgImage: cg)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("garden-\(i).png"))
        }
    }
}

/// The real view in a real window, captured by window id (only this window, never the screen), when GARDEN_LIVE names a folder.
struct GardenHarness: View {
    @State var show = false
    var body: some View {
        GardenCard(url: "focuslink://pair?c=ABCDEFGH&m=00000000-0000-4000-8000-000000000000", showsCode: show) { show.toggle() }
            .padding(20).background(Color(nsColor: .windowBackgroundColor))
            .task { try? await Task.sleep(for: .seconds(2.5)); show = true }
    }
}

@MainActor
final class PairingGardenLiveTests: XCTestCase {
    func testLiveWindow() async throws {
        guard let dir = ProcessInfo.processInfo.environment["GARDEN_LIVE"] else { throw XCTSkip("set GARDEN_LIVE to a folder to capture the live view") }
        let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: GardenHarness()); w.orderFrontRegardless()
        func shot(_ name: String) throws {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-o", "-l", String(w.windowNumber), dir + "/\(name).png"]; try p.run(); p.waitUntilExit()
        }
        try await Task.sleep(for: .seconds(2.0)); try shot("live-tree")
        try await Task.sleep(for: .seconds(0.9)); try shot("live-mid")
        try await Task.sleep(for: .seconds(2.0)); try shot("live-code")
        w.contentView = nil; w.orderOut(nil)
        try await Task.sleep(for: .seconds(0.3))
    }
}
