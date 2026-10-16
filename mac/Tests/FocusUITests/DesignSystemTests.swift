import XCTest
import SwiftUI
@testable import FocusUI

/// The design system's rules (Tokens.swift), checked so a one-off size, radius or tiny target cannot creep back in unnoticed.
@MainActor
final class DesignSystemTests: XCTestCase {
    override func tearDown() { TextScale.shared.factor = 1; super.tearDown() }

    func testTheTypeScaleRisesAndStaysSmall() {
        let sizes = Tokens.Step.allCases.map(\.rawValue)
        XCTAssertEqual(sizes, sizes.sorted(), "steps are in order")
        XCTAssertEqual(Set(sizes).count, sizes.count, "no two steps share a size")
        XCTAssertLessThanOrEqual(sizes.count, 8, "one scale, not a size per screen")
        XCTAssertGreaterThanOrEqual(sizes.first!, 11, "nothing in the window is smaller than 11 pt")
    }

    func testTextSizeIsClampedAndPersistedAndDrivesTheScale() {
        let name = "focus-design-test"
        UserDefaults.standard.removePersistentDomain(forName: name)
        let d = UserDefaults(suiteName: name)!
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.textScale, 1, "default is 100 percent")
        XCTAssertEqual(TextScale.shared.factor, 1)
        p.textScale = 1.3
        XCTAssertEqual(TextScale.shared.factor, 1.3, accuracy: 0.0001, "the setting drives every Tokens font")
        XCTAssertEqual(Preferences(defaults: d).textScale, 1.3, accuracy: 0.0001, "it survives a relaunch")
        d.set(4.0, forKey: "textScale")
        XCTAssertEqual(Preferences(defaults: d).textScale, 1.5, "a stored value out of range is clamped to what the layouts were checked at")
        XCTAssertTrue(TextScale.choices.contains { $0.factor == 1 } && TextScale.choices.allSatisfy { $0.factor >= 1 && $0.factor <= 1.5 })
        UserDefaults.standard.removePersistentDomain(forName: name)
    }

    func testRadiiAndHitTargets() {
        let radii = [Tokens.radiusTiny, Tokens.radiusRow, Tokens.radiusInset, Tokens.radiusCard, Tokens.radiusFloat]
        XCTAssertEqual(radii, radii.sorted(), "a part inside a card is never rounder than the card")
        XCTAssertLessThan(Tokens.radiusInset, Tokens.radiusCard)
        XCTAssertGreaterThanOrEqual(Tokens.minHit, 24, "WCAG 2.2, 2.5.8")
    }

    /// Source scan of the app window's views: every font goes through a type step and every corner radius through a token.
    /// The notch, its shelf and tray, the over-window banner and the menu bar popover keep their own measured geometry and are not scanned.
    func testWindowViewsUseOnlyTokens() throws {
        let views = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FocusUI/Views")
        let skip: Set<String> = ["NotchView.swift", "NotchShelf.swift", "MenuBarContent.swift"]
        let literalFont = try NSRegularExpression(pattern: #"Tokens\.(text|rounded)\(\d"#)
        let literalRadius = try NSRegularExpression(pattern: #"RoundedRectangle\(cornerRadius: \d"#)
        var hits: [String] = []
        for file in try FileManager.default.contentsOfDirectory(atPath: views.path) where file.hasSuffix(".swift") && !skip.contains(file) {
            let text = try String(contentsOf: views.appendingPathComponent(file), encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let l = String(line), r = NSRange(l.startIndex..., in: l)
                if literalFont.firstMatch(in: l, range: r) != nil || literalRadius.firstMatch(in: l, range: r) != nil { hits.append("\(file):\(i + 1)") }
            }
        }
        XCTAssertEqual(hits, [], "use Tokens.Step and the radius tokens")
    }

    /// Nothing that changes every second animates the change. A digit roll or a one-second arc sweep started every second never ends;
    /// together with clocks that each ticked on their own `.now` they kept a demo session at about 40 percent of a core (2026-10-16).
    func testPerSecondClocksDoNotAnimate() throws {
        let ui = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FocusUI")
        var hits: [String] = []
        let files = FileManager.default.enumerator(atPath: ui.path)!.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }
        for file in files {
            let text = try String(contentsOf: ui.appendingPathComponent(file), encoding: .utf8)
            if text.contains("periodic(from: .now, by: 1)") { hits.append("\(file): a one-second timeline off the shared second (use .everySecond)") }
            if text.contains("clockText()") && text.contains("numericText") { hits.append("\(file): a ticking clock with a digit roll") }
            if text.contains("value: state.fraction") { hits.append("\(file): an animated progress arc") }
        }
        XCTAssertEqual(hits, [])
    }
}
