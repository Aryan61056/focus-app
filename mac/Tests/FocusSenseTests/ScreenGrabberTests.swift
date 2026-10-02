import XCTest
import CoreGraphics
@testable import FocusSense

/// The picture must be of the window the user is looking at. Found 2026-10-02 on the owner's Mac: a browser with several windows
/// was captured through its biggest window, not the one in front, so the words read belonged to another page.
final class ScreenGrabberTests: XCTestCase {
    func win(_ pid: Int32, _ number: UInt32, w: CGFloat = 1400, h: CGFloat = 900, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
        [kCGWindowOwnerPID as String: pid, kCGWindowNumber as String: number, kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
         kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": w, "Height": h]]
    }

    func testTheTopmostWindowOfTheAppWinsEvenIfAnotherIsBigger() {
        // Front to back: a small front window of app 7, then a bigger one behind it.
        let list = [win(5, 1), win(7, 20, w: 900, h: 600), win(7, 21, w: 1800, h: 1100)]
        XCTAssertEqual(SCKScreenGrabber.topWindowID(pid: 7, stacking: list), 20)
    }

    func testPanelsToolbarsAndInvisibleWindowsAreSkipped() {
        let list = [win(7, 30, layer: 25), win(7, 31, w: 60, h: 20), win(7, 32, alpha: 0), win(7, 33)]
        XCTAssertEqual(SCKScreenGrabber.topWindowID(pid: 7, stacking: list), 33)
        XCTAssertNil(SCKScreenGrabber.topWindowID(pid: 8, stacking: list))
    }
}
