import XCTest
import FocusJudge
import FocusLinkWire
import FocusLinkCloud
@testable import FocusUI
@testable import FocusLink

/// A stand-in for iCloud: records what the Mac wrote.
@MainActor final class FakeCloud: InsightsSyncing {
    var answer = CloudAvailability.available
    var fail = false
    private(set) var published: [CloudSnapshot] = []
    private(set) var deleted = 0
    func availability() async -> CloudAvailability { answer }
    func publish(_ snapshot: CloudSnapshot) async throws { if fail { throw InsightsCloud.SyncError.plain("You seem to be offline.") }; published.append(snapshot) }
    func fetch() async throws -> CloudSnapshot? { published.last }
    func delete() async throws { deleted += 1; published = [] }
    func listen(onChange: @escaping @MainActor () -> Void) async {}
    func stopListening() async {}
}

@MainActor
final class PhoneSyncTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func defaults() -> UserDefaults { UserDefaults(suiteName: "focus.sync.tests.\(UUID().uuidString)")! }
    func session(_ minutes: Double, task: String = "Calc homework") -> SessionRecord {
        let s = Date().addingTimeInterval(-3_600)
        return SessionRecord(projectId: nil, task: task, timed: false, start: s, end: s.addingTimeInterval(minutes * 60), activeSeconds: minutes * 60,
                             offTopicSeconds: 0, unsureSeconds: 0, drifts: 0, interrupts: 0, refusals: 0, shadowMarks: 0,
                             segments: [TimelineSegment(.on, minutes * 60)], practice: nil)
    }
    var keep: [SessionController] = []   // PhoneSync holds its controller weakly, like the phone link
    func make(_ cloud: FakeCloud, store: DataStore? = nil) -> (PhoneSync, SessionController) {
        let c = SessionController(judge: ScriptedJudge(markers: []), store: store ?? DataStore(), prefs: Preferences(defaults: defaults()))
        let s = PhoneSync(cloud: cloud, defaults: defaults())
        s.attach(c); keep.append(c)
        return (s, c)
    }
    func wait(_ cond: @escaping () -> Bool) async throws {
        let end = Date().addingTimeInterval(5)
        while Date() < end { if cond() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("timed out")
    }

    func testNothingIsWrittenUntilTurnedOn() async throws {
        let cloud = FakeCloud(); let store = DataStore()
        let (sync, _) = make(cloud, store: store)
        store.record(session(30))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(cloud.published.count, 0)
        XCTAssertEqual(sync.status, .off)
    }

    func testTurningOnWritesAndANewSessionWritesAgain() async throws {
        let cloud = FakeCloud(); let store = DataStore()
        let (sync, _) = make(cloud, store: store)
        await sync.setEnabled(true)
        XCTAssertEqual(cloud.published.count, 1)
        if case .ready = sync.status {} else { XCTFail("\(sync.status)") }
        store.record(session(30, task: "Essay outline"))
        try await wait { cloud.published.count == 2 }
        XCTAssertEqual(cloud.published.last?.insights.recent.first?.task, "Essay outline")
    }

    func testAnUnchangedSnapshotIsNotWrittenAgain() async {
        let cloud = FakeCloud()
        let (sync, _) = make(cloud)
        await sync.setEnabled(true)
        await sync.publish(); await sync.publish()
        XCTAssertEqual(cloud.published.count, 1)
    }

    func testNoAccountOrABuildWithoutICloudLeavesItOffAndSaysWhy() async {
        let cloud = FakeCloud(); cloud.answer = .noAccount
        let (sync, _) = make(cloud)
        await sync.setEnabled(true)
        XCTAssertFalse(sync.enabled)
        XCTAssertEqual(sync.status, .unavailable("Sign in to iCloud in System Settings to sync with your phone."))
        cloud.answer = .unavailable("This build of Focus is not set up for iCloud yet.")
        await sync.setEnabled(true)
        XCTAssertFalse(sync.enabled)
        XCTAssertEqual(cloud.published.count, 0)
    }

    func testTurningOffDeletesWhatWasStored() async {
        let cloud = FakeCloud()
        let (sync, _) = make(cloud)
        await sync.setEnabled(true); await sync.setEnabled(false)
        XCTAssertEqual(cloud.deleted, 1)
        XCTAssertEqual(sync.status, .off)
        XCTAssertTrue(cloud.published.isEmpty)
    }

    func testAFailedWriteSaysSoAndKeepsTheSwitch() async {
        let cloud = FakeCloud(); cloud.fail = true
        let (sync, _) = make(cloud)
        await sync.setEnabled(true)
        XCTAssertTrue(sync.enabled)
        XCTAssertEqual(sync.status, .failed("You seem to be offline."))
        cloud.fail = false
        await sync.publish()
        if case .ready = sync.status {} else { XCTFail("\(sync.status)") }
    }

    func testThePhoneNeverReceivesPracticeSessions() async {
        let cloud = FakeCloud(); let store = DataStore()
        var practice = session(20); practice.practice = true
        store.record(practice)
        let (sync, _) = make(cloud, store: store)
        await sync.setEnabled(true)
        XCTAssertTrue(cloud.published.last?.insights.recent.isEmpty ?? false)
    }
}
