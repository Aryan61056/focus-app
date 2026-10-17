import XCTest
import AppKit
@testable import FocusUI

@MainActor final class NotchHapticsTests: XCTestCase {
    func testEachMomentHasAShapeAndPressNeverOutweighsOpen() {
        XCTAssertEqual(NotchHaptics.Kind.pressed.pattern, .alignment)
        XCTAssertEqual(NotchHaptics.Kind.page.pattern, .alignment)
        XCTAssertEqual(NotchHaptics.Kind.entered.pattern, .alignment)
        XCTAssertEqual(NotchHaptics.Kind.opened.pattern, .levelChange)
        XCTAssertEqual(NotchHaptics.Kind.landed.pattern, .levelChange)
    }

    func testOnByDefaultAndSavedAcrossLaunches() {
        let suite = "focus.tests.\(UUID().uuidString)"
        let a = Preferences(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(a.notchHaptics)
        a.notchHaptics = false
        XCTAssertFalse(Preferences(defaults: UserDefaults(suiteName: suite)!).notchHaptics)
    }

    func testNoHapticFromHoverAnywhereInTheNotch() throws {
        // Hovering happens dozens of times a day, so nothing under onHover or the hover model may tap.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FocusUI/Views/NotchView.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("model.hover) { _, _ in haptic"), "hover must not tap")
        XCTAssertFalse(text.range(of: #"onChange\(of: model\.hover\)[^\n]*haptic"#, options: .regularExpression) != nil, "hover must not tap")
    }
}
