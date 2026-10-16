import XCTest
@testable import FocusUI

/// The Workspace pieces that turn readings into pictures: the session band, the windows tally and "What Focus did".
@MainActor
final class WorkspaceTests: XCTestCase {
    func r(_ at: Double, _ app: String, _ call: Reading.Call, source: Reading.Source = .model, key: String? = nil, byWords: Bool = false) -> Reading {
        Reading(at: at, date: Date(timeIntervalSince1970: at), key: key ?? app, app: app, title: "", call: call, source: source, reason: "because", byWords: byWords)
    }

    func testStretchesFollowTheReadingsAndMergeRepeats() {
        // Newest first, as the controller keeps them.
        let rs = [r(70, "Notes", .on), r(40, "Safari", .off), r(20, "Notes", .on), r(10, "Notes", .on)]
        let s = SessionTimeline.stretches(rs, start: 0, now: 100)
        XCTAssertEqual(s.map(\.call), [nil, .on, .off, .on], "a gap before the first window, then one stretch per change of call")
        XCTAssertEqual(s.map(\.from), [0, 10, 40, 70])
        XCTAssertEqual(s.map(\.to), [10, 40, 70, 100], "each reading holds until the next; the last until now")
        XCTAssertEqual(s[1].id, rs[3].id, "a merged stretch keeps the first reading, so tapping it shows that reason")
    }

    func testStretchesIgnoreReadingsFromBeforeTheSession() {
        let s = SessionTimeline.stretches([r(5, "Notes", .on), r(-50, "Old", .off)], start: 0, now: 30)
        XCTAssertEqual(s.map(\.call), [nil, .on], "the earlier reading is dropped; the five seconds before the first window stay empty")
        XCTAssertEqual(s.last?.from, 5)
    }

    func testWindowsTallyByTimeAndLeavesPrivateOnesOut() {
        let rs = [r(90, "Notes", .on), r(60, "Private", .on, source: .sensitive), r(30, "Safari", .unsure), r(0, "Notes", .on)]
        let rows = SessionWindows.rows(rs, start: 0, now: 120)
        XCTAssertEqual(rows.map(\.app), ["Notes", "Safari"], "longest first; a private window is never listed")
        XCTAssertEqual(rows.first?.seconds, 60)
        XCTAssertEqual(rows.last?.call, .unsure)
    }

    func testActivityLogSaysWhatFocusDidInAFewWords() {
        let rs = [r(50, "Notes", .on), r(40, "Safari", .off), r(30, "Messages", .unsure, source: .skipped), r(20, "Notes", .on, byWords: true), r(10, "Notes", .on, byWords: true)]
        let e = ActivityLog.entries(rs, limit: 6)
        XCTAssertEqual(e.map(\.kind), [.back, .offTopic, .skipped, .counted], "newest first; a repeat of the same window and call is one line")
        XCTAssertEqual(e.last?.detail, "on task")
        XCTAssertTrue(e.allSatisfy { $0.title.split(separator: " ").count <= 6 }, "a few words each, not sentences")
        XCTAssertEqual(ActivityLog.entries(rs, limit: 2).count, 2)
    }

    func testMatchedWordsReadAsAShortBasis() {
        XCTAssertEqual(VerdictView.matched("Its app name, title or address shares words with your task: calc."), "Matches calc")
        XCTAssertEqual(VerdictView.matched("No colon here"), "Matching words")
    }

    func testCountsRead() {
        XCTAssertEqual(SessionCounts.minutes(42), "42 s")
        XCTAssertEqual(SessionCounts.minutes(9 * 60 + 5), "9 min")
        XCTAssertEqual(SessionCounts.minutes(3600 + 10 * 60), "1 h 10 min")
    }
}
