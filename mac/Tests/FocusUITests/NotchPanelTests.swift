import XCTest
import AppKit
@testable import FocusUI
@testable import FocusJudge

/// Regression for the 2026-10-01 crashes (hovering the notch, unplugging a monitor): both were an AppKit layout loop
/// from SwiftUI sizing the notch window. These drive the real panel on the real screen; they cannot unplug a display.
@MainActor
final class NotchPanelTests: XCTestCase {
    private func spin(_ s: Double = 0.05) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    func testTheRingStaysOnTheNotchedScreenNotOnWhicheverIsMain() {
        XCTAssertEqual(NotchPanelController.homeIndex(notchWidths: [0, 200]), 1, "external primary, notched built-in second")
        XCTAssertEqual(NotchPanelController.homeIndex(notchWidths: [200, 0]), 0)
        XCTAssertEqual(NotchPanelController.homeIndex(notchWidths: [0, 0]), 0, "no notch anywhere: the primary screen")
        XCTAssertEqual(NotchPanelController.homeIndex(notchWidths: [0]), 0)
        XCTAssertNil(NotchPanelController.homeIndex(notchWidths: []), "no screen: nothing to show")
    }

    func testHoverAndScreenChangesDoNotCrashAndTheFrameFollowsTheMode() async throws {
        _ = NSApplication.shared
        guard NSScreen.main != nil else { throw XCTSkip("no screen") }
        var t = 0.0
        let c = SessionController(judge: ScriptedJudge(markers: [("Notes", .on)]), now: { t })
        c.prefs.showNotch = true
        let panel = NotchPanelController(controller: c, openApp: {})
        panel.start(); defer { panel.stop() }
        await spin()
        XCTAssertFalse(panel.isShowing, "hidden until a session runs")

        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await spin()
        XCTAssertTrue(panel.isShowing)
        let restH = try XCTUnwrap(panel.shownSizeForTesting).height
        let windowH = try XCTUnwrap(panel.frameForTesting).height
        let screens = NSScreen.screens
        if let hi = NotchPanelController.homeIndex(notchWidths: screens.map { NotchPanelController.geometry($0).width }), NotchPanelController.geometry(screens[hi]).width == 0 {
            XCTAssertLessThanOrEqual(try XCTUnwrap(panel.frameForTesting).maxY, screens[hi].visibleFrame.maxY, "the pill sits under the menu bar, not over it")
        }
        XCTAssertEqual(panel.framesForTesting.count, 1, "one panel at rest, however many displays")

        for _ in 0..<50 { panel.setHoverForTesting(true); await spin(0.01); panel.setHoverForTesting(false); await spin(0.01) }
        panel.setHoverForTesting(true); await spin()
        XCTAssertGreaterThan(try XCTUnwrap(panel.shownSizeForTesting).height, restH)
        XCTAssertEqual(try XCTUnwrap(panel.frameForTesting).height, windowH, "the window itself never resizes with the mode")
        panel.setHoverForTesting(false); await spin()
        XCTAssertEqual(try XCTUnwrap(panel.shownSizeForTesting).height, restH)

        // What macOS posts when a display is added or removed.
        for _ in 0..<20 { NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil); await spin(0.01) }
        XCTAssertTrue(panel.isShowing)

        c.end(); await spin()
        XCTAssertFalse(panel.isShowing, "hidden when the session ends")
    }
}
