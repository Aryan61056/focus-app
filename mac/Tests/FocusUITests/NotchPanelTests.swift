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
        let panel = NotchPanelController(controller: c)
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
        XCTAssertTrue(panel.anyWindowVisibleForTesting, "it tucks back into the notch before the window goes")
        await spin(NotchPanelController.tuckSeconds + 0.2)
        XCTAssertFalse(panel.anyWindowVisibleForTesting, "and the window is gone once the tuck is done")
    }

    /// Owner, 2026-10-15: bugs around the notch. The window is bigger than the shape, and it used to swallow every click in its frame,
    /// so the menu bar next to the notch and a browser's tab bar could not be clicked for a whole session.
    func testClicksPassThroughEverythingExceptTheShape() async throws {
        _ = NSApplication.shared
        guard NSScreen.main != nil else { throw XCTSkip("no screen") }
        let c = SessionController(judge: ScriptedJudge(markers: [("Notes", .on)]), now: { 0 })
        c.prefs.showNotch = true
        let panel = NotchPanelController(controller: c)
        panel.start(); defer { panel.stop() }
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await spin()
        let box = try XCTUnwrap(panel.hoverBoxForTesting), win = try XCTUnwrap(panel.panelForTesting)
        let shape = try XCTUnwrap(box.shapeOnScreen()), frame = win.frame
        XCTAssertGreaterThan(frame.height, shape.height + 20, "the window is bigger than the resting shape")

        box.pointerMoved(at: NSPoint(x: shape.midX, y: shape.minY - 30))   // in the window, under the shape
        XCTAssertTrue(win.ignoresMouseEvents, "empty window area lets the click through")
        box.pointerMoved(at: NSPoint(x: frame.minX - 50, y: frame.midY))
        XCTAssertTrue(win.ignoresMouseEvents)
        box.pointerMoved(at: NSPoint(x: shape.midX, y: shape.midY))
        XCTAssertFalse(win.ignoresMouseEvents, "the shape itself takes clicks (Back to task)")
        box.pointerMoved(at: NSPoint(x: shape.midX, y: shape.minY - 30))
        XCTAssertTrue(win.ignoresMouseEvents, "and lets go again when the pointer leaves it")

        c.end(); await spin(NotchPanelController.tuckSeconds + 0.2)
    }

    /// Owner, 2026-10-15: "the notch doesn't collapse when I don't hover over it". A click that came before the hover delay had run
    /// opened the card without the hover ever registering, so leaving did nothing.
    func testAClickBeforeTheHoverDelayStillClosesWhenThePointerLeaves() async throws {
        _ = NSApplication.shared
        guard NSScreen.main != nil else { throw XCTSkip("no screen") }
        let c = SessionController(judge: ScriptedJudge(markers: [("Notes", .on)]), now: { 0 })
        c.prefs.showNotch = true
        let panel = NotchPanelController(controller: c)
        panel.start(); defer { panel.stop() }
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await spin()
        let box = try XCTUnwrap(panel.hoverBoxForTesting)
        let rest = try XCTUnwrap(panel.shownSizeForTesting).height
        let shape = try XCTUnwrap(box.shapeOnScreen())
        func move(_ p: NSPoint) { box.pointerForTesting = p; box.pointerMoved() }

        move(NSPoint(x: shape.midX, y: shape.midY))   // arrives
        panel.setExpandedForTesting(true)                            // and clicks at once, before the 0.2 s hover delay
        await spin(0.1)
        XCTAssertGreaterThan(try XCTUnwrap(panel.shownSizeForTesting).height, rest, "the click opened it")
        move(NSPoint(x: shape.midX, y: shape.minY - 300))   // leaves
        await spin(0.6)
        XCTAssertEqual(try XCTUnwrap(panel.shownSizeForTesting).height, rest, "and leaving closes it")

        // And the ordinary way: hover long enough to register, click, leave.
        move(NSPoint(x: shape.midX, y: shape.midY)); await spin(0.5)
        panel.setExpandedForTesting(true); await spin(0.1)
        move(NSPoint(x: shape.midX, y: shape.minY - 300)); await spin(0.6)
        XCTAssertEqual(try XCTUnwrap(panel.shownSizeForTesting).height, rest)
        c.end(); await spin(NotchPanelController.tuckSeconds + 0.2)
    }
}

/// The notch is for looking. These fail if a way out of a nudge is ever put back on it (owner, 2026-10-13).
final class NotchHasNoWayOutTests: XCTestCase {
    func testTheNotchSourceHasOnlyBackToTaskAsAnAction() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FocusUI/Views/NotchView.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        let actions = src.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }.joined(separator: "\n")
        for banned in [".pause", ".resume", ".dismiss", ".snooze", ".breakTime", "takeNudgeBreak", "rhythmTakeBreak", "rhythmKeepGoing", "answerCheckIn", "claimOnTask", "leaveGate", "requestEnd", "end()", "openApp", "Not now", "Yes, I am", "Take a break", "Open Focus", "Resume", "Pause"] {
            XCTAssertFalse(actions.contains(banned), "the notch must not offer \(banned)")
        }
        XCTAssertEqual(actions.components(separatedBy: "pill(\"").count - 1, 1, "one button only")
        XCTAssertTrue(actions.contains("c.act(.backToTask)"))
    }
}
