import XCTest
@testable import FocusUI

/// What the start form offers: the recent projects in the order you used them, and a plain line for each length.
@MainActor final class StartFormTests: XCTestCase {
    private func session(_ store: DataStore, _ p: Project, at t: Double) {
        let start = Date(timeIntervalSince1970: t)
        store.record(SessionRecord(projectId: p.id, task: p.name, timed: false, start: start, end: start.addingTimeInterval(600), activeSeconds: 600,
                                   offTopicSeconds: 0, unsureSeconds: 0, drifts: 0, interrupts: 0, refusals: 0, shadowMarks: 0, segments: []))
    }

    func testRecentProjectsListTheOnesYouUsedLastFirst() {
        let store = DataStore()
        let a = store.addProject(name: "A"), c = store.addProject(name: "C")
        _ = store.addProject(name: "B"); _ = store.addProject(name: "D")   // never used; the store lists the newest created first (D, B, C, A)
        session(store, c, at: 200); session(store, a, at: 300)
        XCTAssertEqual(StartSheet.recentProjects(store).map(\.name), ["A", "C", "D"], "used newest first, then never used newest created first")
        XCTAssertEqual(StartSheet.recentProjects(store, limit: 2).map(\.name), ["A", "C"])
        XCTAssertEqual(StartSheet.recentProjects(store).first?.id, StartSheet.lastProject(store)?.id, "the first one offered is the one Return continues")
    }

    func testRecentProjectsWithNoStoreOrNoHistory() {
        XCTAssertTrue(StartSheet.recentProjects(nil).isEmpty)
        let store = DataStore()
        XCTAssertTrue(StartSheet.recentProjects(store).isEmpty)
        _ = store.addProject(name: "Only")
        XCTAssertEqual(StartSheet.recentProjects(store).map(\.name), ["Only"])
        XCTAssertNil(StartSheet.lastProject(store), "nothing to continue until a session has run")
    }

    func testTheSliderStopsAreFineAtFirstAndEndWithOpen() {
        let stops = LengthStops.minutes
        XCTAssertEqual(stops.first, 5, "the short start is the first stop")
        XCTAssertEqual(stops, stops.sorted(), "stops only grow")
        let gaps = zip(stops, stops.dropFirst()).map { $1 - $0 }
        XCTAssertEqual(gaps.first, 5, "five-minute steps at the start")
        XCTAssertGreaterThan(gaps.last ?? 0, gaps.first ?? 0, "wider steps further out")
        XCTAssertEqual(LengthStops.open, stops.count, "the last stop is Open")
        XCTAssertEqual(LengthStops.minutes[LengthStops.nearest(27)], 25)
        XCTAssertEqual(LengthStops.minutes[LengthStops.nearest(1000)], 180)
        XCTAssertEqual(LengthStops.minutes[LengthStops.nearest(0)], 5)
    }

    func testLengthsReadInPlainWords() {
        XCTAssertEqual(LengthStops.describe(minutes: 5), "5 min")
        XCTAssertEqual(LengthStops.describe(minutes: 45), "45 min")
        XCTAssertEqual(LengthStops.describe(minutes: 60), "1 hour")
        XCTAssertEqual(LengthStops.describe(minutes: 90), "1 h 30 min")
        XCTAssertEqual(LengthStops.describe(minutes: 120), "2 hours")
    }

    func testTheSliderPlansTheSessionItShows() {
        let draft = StartDraft(), now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(draft.plan(now: now)?.mode, .open, "a new draft is Open, the starting point for everyone without a habit")
        draft.length = .minutes; draft.minutes = 40
        XCTAssertEqual(draft.plan(now: now)?.duration, 2400)
        XCTAssertEqual(draft.plan(now: now)?.five, false)
        draft.minutes = 5
        XCTAssertEqual(draft.plan(now: now)?.five, true, "five minutes keeps the offer to keep going")
        XCTAssertEqual(draft.plan(now: now, text: "Essay 50")?.duration, 3000, "a length typed in the name still wins")
    }

    private func record(_ minutes: Double, timed: Bool, daysAgo: Double) -> SessionRecord {
        let start = Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86400)
        return SessionRecord(projectId: nil, task: "t", timed: timed, start: start, end: start.addingTimeInterval(minutes * 60), activeSeconds: minutes * 60,
                             offTopicSeconds: 0, unsureSeconds: 0, drifts: 0, interrupts: 0, refusals: 0, shadowMarks: 0, segments: [])
    }

    func testTheUsualLengthComesOnlyFromAHabitOfTimedSessions() {
        XCTAssertNil(LengthStops.usualMinutes(from: []), "no history, no suggestion")
        XCTAssertNil(LengthStops.usualMinutes(from: [record(50, timed: true, daysAgo: 1), record(50, timed: true, daysAgo: 2)]), "two sessions are not a habit")
        let open = (1...8).map { record(60, timed: false, daysAgo: Double($0)) }
        XCTAssertNil(LengthStops.usualMinutes(from: open + [record(50, timed: true, daysAgo: 9)]), "mostly Open sessions stay on Open")
        let habit = [record(48, timed: true, daysAgo: 1), record(52, timed: true, daysAgo: 2), record(45, timed: true, daysAgo: 3), record(25, timed: false, daysAgo: 4)]
        XCTAssertEqual(LengthStops.usualMinutes(from: habit), 50, "the middle of 45, 48 and 52 is 48, which is nearest the 50 stop")
        let withShort = habit + [record(5, timed: true, daysAgo: 5), record(6, timed: true, daysAgo: 6)]
        XCTAssertEqual(LengthStops.usualMinutes(from: withShort), 50, "short starts do not drag the usual length down")
    }
}
