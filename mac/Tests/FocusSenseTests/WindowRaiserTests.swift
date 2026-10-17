import XCTest
@testable import FocusSense
import FocusUI

/// Which window "Back to task" raises. The raising itself needs Accessibility and a real app, so only the choice is tested here.
final class WindowRaiserTests: XCTestCase {
    typealias C = WindowRaiser.Candidate
    func win(_ app: String, _ title: String, doc: String = "") -> WindowSnapshot { WindowSnapshot(app: app, title: title, documentPath: doc) }

    func testTheSameFileWinsEvenIfTheTitleChanged() {
        let cands = [C(title: "Other", documentPath: "/a/Other.pages"), C(title: "Essay \u{2014} Edited", documentPath: "/a/Essay.pages")]
        XCTAssertEqual(WindowRaiser.pick(for: win("Pages", "Essay", doc: "/a/Essay.pages"), among: cands), 1)
    }

    func testTheSameTitleWhenThereIsNoFile() {
        let cands = [C(title: "FocusApp \u{2014} Brain.swift"), C(title: "FocusApp \u{2014} Cues.swift"), C(title: "Scratch")]
        XCTAssertEqual(WindowRaiser.pick(for: win("Xcode", "FocusApp \u{2014} Cues.swift"), among: cands), 1)
    }

    func testABrowsersOwnNameAtTheEndDoesNotGetInTheWay() {
        let cands = [C(title: "Inbox - Google Chrome"), C(title: "Lecture notes - Google Chrome")]
        XCTAssertEqual(WindowRaiser.pick(for: win("Google Chrome", "Lecture notes"), among: cands), 1)
    }

    func testATitleThatGainedAnEditMarkIsStillFoundWhenItIsTheOnlyCandidate() {
        let cands = [C(title: "Budget 2026 - Edited"), C(title: "Letter")]
        XCTAssertEqual(WindowRaiser.pick(for: win("Numbers", "Budget 2026"), among: cands), 0)
    }

    func testAnAmbiguousPartialMatchIsNilBecauseTheWrongWindowIsWorseThanTheApp() {
        let cands = [C(title: "Project plan - draft one"), C(title: "Project plan - draft two")]
        XCTAssertNil(WindowRaiser.pick(for: win("Pages", "Project plan"), among: cands))
    }

    func testShortTitlesAreNeverGuessed() {
        XCTAssertNil(WindowRaiser.pick(for: win("Notes", "Todo"), among: [C(title: "Todo list for Friday")]))
    }

    func testNothingToGoOnIsNil() {
        XCTAssertNil(WindowRaiser.pick(for: win("Notes", ""), among: [C(title: "Anything")]))
        XCTAssertNil(WindowRaiser.pick(for: win("Notes", "Plan"), among: []))
    }
}
