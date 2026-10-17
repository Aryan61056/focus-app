import XCTest
import CloudKit
@testable import FocusLinkCloud
import FocusLinkWire

/// The record mapping and the day roll only: nothing here talks to iCloud, which needs a signed build.
final class InsightsCloudTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    let zone = CKRecordZone.ID(zoneName: "Sync", ownerName: CKCurrentUserDefaultName)
    func day(_ d: Int, _ h: Int = 10) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))! }

    func insights() -> Insights {
        Insights(todayOnTaskSeconds: 2_700, goalMinutes: 90, streak: 4, bestStreak: 9, restDaysUsed: 1,
                 week: [Insights.Day(day: day(16, 0), onTaskSeconds: 2_700, mark: .focus)],
                 recent: [Insights.Digest(id: UUID(), task: "Calc homework", start: day(16), end: day(16, 11), onTaskSeconds: 2_700, activeSeconds: 3_000, drifts: 1, practice: false)],
                 bestStretchSeconds: 1_500, returnSeconds: 12, returnCount: 3)
    }

    func testASnapshotSurvivesTheTripAndIsOnlyInEncryptedFields() throws {
        let snap = CloudSnapshot(asOf: day(16), insights: insights())
        let r = try SnapshotRecord.make(snap, zone: zone)
        XCTAssertNil(r["snapshot"], "only in encryptedValues, so iCloud cannot read the task names")
        XCTAssertEqual(r.recordID.recordName, "insights", "one record, replaced each time")
        XCTAssertEqual(SnapshotRecord.decode(r), snap)
    }

    func testAForeignOrBrokenRecordIsIgnored() throws {
        let other = CKRecord(recordType: "Other", recordID: CKRecord.ID(recordName: "insights", zoneID: zone))
        other.encryptedValues["snapshot"] = Data("{}".utf8)
        XCTAssertNil(SnapshotRecord.decode(other))
        let broken = try SnapshotRecord.make(CloudSnapshot(asOf: day(16), insights: insights()), zone: zone)
        broken.encryptedValues["snapshot"] = Data("not json".utf8)
        XCTAssertNil(SnapshotRecord.decode(broken))
    }

    func testAnOldSnapshotClaimsNoTimeForToday() {
        let snap = CloudSnapshot(asOf: day(15, 22), insights: insights())
        XCTAssertEqual(snap.shown(now: day(16), calendar: cal).todayOnTaskSeconds, 0)
        XCTAssertEqual(snap.shown(now: day(15, 23), calendar: cal).todayOnTaskSeconds, 2_700)
        XCTAssertEqual(snap.shown(now: day(16), calendar: cal).streak, 4, "the rest still shows, labelled with its date")
    }

    @MainActor func testWithoutAContainerEverythingSaysNotSetUp() async {
        let cloud = InsightsCloud(containerID: nil)
        let a = await cloud.availability()
        guard case .unavailable = a else { return XCTFail("\(a)") }
        do { _ = try await cloud.fetch(); XCTFail("should throw") } catch { XCTAssertTrue(error.localizedDescription.contains("not set up")) }
        do { try await cloud.publish(CloudSnapshot(asOf: Date(), insights: Insights())); XCTFail("should throw") } catch { }
    }

    @MainActor func testErrorsBecomePlainSentences() {
        XCTAssertTrue(InsightsCloud.say(CKError(.networkUnavailable)).contains("offline"))
        XCTAssertEqual(InsightsCloud.say(CKError(.quotaExceeded)), "Your iCloud storage is full.")
        XCTAssertEqual(InsightsCloud.say(CKError(.internalError)), "Could not reach iCloud. Try again in a moment.")
    }
}
