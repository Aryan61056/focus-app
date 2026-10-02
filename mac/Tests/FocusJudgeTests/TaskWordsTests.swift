import XCTest
@testable import FocusJudge

final class TaskWordsTests: XCTestCase {
    func m(task: String, title: String, url: String = "", path: String = "", context: String = "") -> Moment {
        var p = ProjectProfile(); p.context = context
        return Moment(task: task, app: "App", windowTitle: title, url: url, documentPath: path, windowText: "", project: p)
    }

    func testSharedWordsComeFromTheTitlePathAndFileNotJustAnyText() {
        XCTAssertEqual(Rules.sharedTaskWords(m(task: "Fix the pagination bug in the orders API", title: "orders_api.py - orders-service")), ["orders"])
        XCTAssertEqual(Rules.sharedTaskWords(m(task: "Write the methods section of my chemistry lab report", title: "Titration - Chemistry LibreTexts", url: "https://chem.libretexts.example/titration")), ["chemistry"])
        XCTAssertEqual(Rules.sharedTaskWords(m(task: "Calc homework", title: "Notes", path: "/Users/a/Documents/calculus-chapter5.pdf", context: "Calculus II, integration by parts")), ["calculus"])
        XCTAssertTrue(Rules.sharedTaskWords(m(task: "Fix the pagination bug in the orders API", title: "Funniest cat videos")).isEmpty)
    }

    func testStopWordsAndShortWordsNeverMatch() {
        XCTAssertTrue(Rules.sharedTaskWords(m(task: "Write the report for work", title: "Work notes about the new page")).isEmpty)
    }

    func testFeedsVideoAndNewsAreExcludedEvenWithAMatchingWord() {
        XCTAssertTrue(Rules.sharedTaskWords(m(task: "Study organic chemistry", title: "Organic chemistry memes", url: "https://www.youtube.com/watch?v=1")).isEmpty)
        XCTAssertTrue(Rules.sharedTaskWords(m(task: "Build the pitch deck", title: "Pitch deck disasters", url: "https://old.reddit.com/r/startups")).isEmpty)
    }

    /// Cost of the rule, measured on every scenario set: how many off-task or unsure moments it would wave through, and how many on-task ones it settles.
    func testOnTheScenarioSetsItSettlesManyOnTaskMomentsAndAlmostNoOffTaskOnes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("eval")
        var on = (hit: 0, n: 0), off = (hit: 0, n: 0), unsure = (hit: 0, n: 0)
        for dir in ["scenarios", "scenarios_heldout", "scenarios_fresh"] {
            for s in try Scenario.loadAll(directory: root.appendingPathComponent(dir)) {
                let hit = !Rules.sharedTaskWords(s.moment).isEmpty
                switch s.label {
                case .onTask: on.n += 1; on.hit += hit ? 1 : 0
                case .offTask: off.n += 1; off.hit += hit ? 1 : 0
                case .unsure: unsure.n += 1; unsure.hit += hit ? 1 : 0
                }
            }
        }
        print("TASKWORDS on_task \(on.hit)/\(on.n), off_task \(off.hit)/\(off.n), unsure \(unsure.hit)/\(unsure.n)")
        XCTAssertGreaterThan(Double(on.hit) / Double(on.n), 0.4)
        XCTAssertLessThanOrEqual(off.hit, 3, "a quiet rule must not wave through many real distractions")
        XCTAssertLessThanOrEqual(unsure.hit, 2)
    }
}
