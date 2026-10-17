import XCTest
import FocusBrain
import FocusJudge
@testable import FocusUI

@MainActor final class StartFlowTests: XCTestCase {
    func testLengthChoicesAndTypedLength() {
        let draft = StartDraft(); let now = Date(timeIntervalSince1970: 1700000000)
        XCTAssertEqual(draft.plan(now: now)?.mode, .open)
        draft.length = .minutes; draft.minutes = 5; XCTAssertEqual(draft.plan(now: now)?.duration, 300); XCTAssertTrue(draft.plan(now: now)?.five == true)
        draft.length = .minutes; draft.minutes = 25; XCTAssertEqual(draft.plan(now: now)?.duration, 1500)
        draft.task = "Essay 50"; XCTAssertEqual(draft.plan(now: now)?.duration, 3000)
        XCTAssertEqual(draft.plan(now: now, text: "Chemistry")?.duration, 1500, "Quick project start does not inherit another typed task's suffix")
    }
    func testClockTimeRollover() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 16, minute: 45)))
        let choice = now.addingTimeInterval(-15 * 60)
        let result = try XCTUnwrap(StartDraft.nextClockTime(choice, after: now, calendar: calendar))
        XCTAssertEqual(calendar.component(.day, from: result), 16); XCTAssertEqual(calendar.component(.hour, from: result), 16); XCTAssertEqual(calendar.component(.minute, from: result), 30)
    }
    func testAbsoluteDeadlineKeepsCountingThroughPauseAndEndsBeforeAnotherReading() {
        var t = 0.0; let base = Date(timeIntervalSince1970: 1700000000)
        let c = SessionController(judge: UnsureJudge(), store: DataStore(), now: { t }, date: { base.addingTimeInterval(t) })
        c.begin(task: "Chemistry", mode: .timed, duration: 180, deadline: base.addingTimeInterval(180), goal: "Answer the first question")
        t = 60; c.tick(); XCTAssertTrue(c.wrapUp); c.act(.pause)
        t = 100; XCTAssertEqual(c.clockSeconds(), 80, accuracy: 0.01)
        t = 180; c.windowChanged(WindowSnapshot(app: "Synthetic browser", title: "Synthetic feed"))
        XCTAssertFalse(c.isActive); XCTAssertNil(c.surface); XCTAssertEqual(c.summary?.activeSeconds ?? -1, 60, accuracy: 0.01)
        XCTAssertNil(c.sessionDeadline); XCTAssertEqual(c.store?.sessions.first?.goal, "Answer the first question")
    }
    func testFiveMinutesOffersAChoiceAndContinuingCreatesAnOpenSession() {
        var t = 0.0
        let c = SessionController(judge: UnsureJudge(), store: DataStore(), now: { t })
        c.startDraft.task = "Chemistry"; c.startDraft.length = .minutes; c.startDraft.minutes = 5; c.startDraft.done = "Answer the first question"
        XCTAssertTrue(c.startWithDraft(autoTick: false))
        t = 300; c.tick(); XCTAssertFalse(c.isActive); XCTAssertTrue(c.shortSessionOffer)
        c.keepGoing(); XCTAssertTrue(c.isActive); XCTAssertEqual(c.mode, .open); XCTAssertFalse(c.shortSessionOffer)
        XCTAssertEqual(c.store?.sessions.count, 1); XCTAssertEqual(c.store?.sessions.first?.goalDone, false)
        XCTAssertEqual(c.sessionGoal, "Answer the first question"); c.end()
    }
    func testManualEarlyEndDoesNotOfferContinuationAndGoalCanBeCarriedThenCompleted() {
        let c = SessionController(judge: UnsureJudge(), store: DataStore())
        c.startDraft.task = "Essay"; c.startDraft.length = .minutes; c.startDraft.minutes = 5; c.startDraft.done = "Write the opening paragraph"
        XCTAssertTrue(c.startWithDraft(autoTick: false)); c.end(); XCTAssertFalse(c.shortSessionOffer)
        c.resolveSessionGoal(done: false)
        XCTAssertEqual(c.projectForNote?.carriedGoal, "Write the opening paragraph")
        XCTAssertTrue(c.startWithDraft(autoTick: false)); XCTAssertEqual(c.sessionGoal, "Write the opening paragraph")
        c.end(); c.resolveSessionGoal(done: true)
        XCTAssertNil(c.projectForNote?.carriedGoal); XCTAssertEqual(c.store?.sessions.first?.goalDone, true)
    }
    func testLongResultIsRetainedAndDoesNotStart() {
        let c = SessionController(judge: UnsureJudge(), store: DataStore())
        c.startDraft.task = "Essay"; c.startDraft.done = String(repeating: "a", count: 241)
        XCTAssertFalse(c.startWithDraft(autoTick: false)); XCTAssertEqual(c.startDraft.done.count, 241)
    }
    func testLegacyProjectAndSessionDecodeWithNoGoal() throws {
        let store = DataStore(); let project = store.addProject(name: "Synthetic project")
        let record = SessionRecord(projectId: project.id, task: project.name, timed: false, start: Date(), end: Date(), activeSeconds: 2, offTopicSeconds: 0, unsureSeconds: 0, drifts: 0, interrupts: 0, refusals: 0, shadowMarks: 0, segments: [])
        let encoded = try JSONEncoder().encode(record), restored = try JSONDecoder().decode(SessionRecord.self, from: encoded)
        XCTAssertNil(restored.goal); XCTAssertNil(restored.goalDone)
        XCTAssertNil(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project)).carriedGoal)
    }
    func testExpiredDeadlineCannotBeExtendedBackIntoAnActiveSession() {
        var t = 0.0; let base = Date(timeIntervalSince1970: 1700000000)
        let c = SessionController(judge: UnsureJudge(), store: DataStore(), now: { t }, date: { base.addingTimeInterval(t) })
        c.begin(task: "Essay", mode: .timed, duration: 60, deadline: base.addingTimeInterval(60))
        t = 61; c.act(.extend, minutes: 5)
        XCTAssertFalse(c.isActive); XCTAssertNil(c.sessionDeadline)
    }
    func testGoalPersistenceAcrossReloadAndQuickProjectStartIsolation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("store.json"), store = DataStore(url: url)
        let c = SessionController(judge: UnsureJudge(), store: store)
        c.startDraft.task = "Essay"; c.startDraft.done = "Write the first paragraph"
        XCTAssertTrue(c.startWithDraft(autoTick: false)); c.end(); c.resolveSessionGoal(done: false)
        let restored = DataStore(url: url)
        XCTAssertEqual(restored.sessions.first?.goal, "Write the first paragraph"); XCTAssertEqual(restored.sessions.first?.goalDone, false)
        XCTAssertEqual(restored.projects.first?.carriedGoal, "Write the first paragraph")
        let other = store.addProject(name: "Chemistry")
        c.startDraft.task = "Essay 50"; c.startDraft.done = "Unrelated essay goal"; c.startDraft.length = .minutes; c.startDraft.minutes = 25
        XCTAssertTrue(c.startWithDraft(task: other.name, projectId: other.id, autoTick: false))
        XCTAssertEqual(c.clockSeconds(), 1500, accuracy: 1); XCTAssertEqual(c.sessionGoal, ""); c.end()
    }

}
