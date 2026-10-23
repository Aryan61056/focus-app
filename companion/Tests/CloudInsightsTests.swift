import Testing
import Foundation
import FocusLinkWire
import FocusLinkCloud
@testable import FocusCompanion

/// A stand-in for iCloud.
final class StubCloud: InsightsSyncing {
    var answer = CloudAvailability.available
    var snapshot: CloudSnapshot?
    var fail = false
    func availability() async -> CloudAvailability { answer }
    func publish(_ snapshot: CloudSnapshot) async throws {}
    func fetch() async throws -> CloudSnapshot? { if fail { throw InsightsCloud.SyncError.plain("You seem to be offline.") }; return snapshot }
    func delete() async throws {}
    func listen(onChange: @escaping @MainActor () -> Void) async {}
    func stopListening() async {}
}

struct CloudInsightsTests {
    func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("cloud-\(UUID().uuidString).json") }
    func snap(_ asOf: Date = Date(), streak: Int = 3) -> CloudSnapshot { CloudSnapshot(asOf: asOf, insights: Insights(todayOnTaskSeconds: 600, streak: streak)) }

    @Test func refreshShowsWhatTheMacWroteAndKeepsACopyForOffline() async {
        let stub = StubCloud(); stub.snapshot = snap()
        let file = url()
        let c = CloudInsights(cloud: stub, cacheURL: file)
        await c.refresh()
        #expect(c.snapshot?.insights.streak == 3)
        #expect(c.status == .ready)
        let again = CloudInsights(cloud: StubCloud(), cacheURL: file)   // a new launch, before iCloud answers
        #expect(again.snapshot?.insights.streak == 3)
    }

    @Test func aMacThatTurnedItOffClearsThePhone() async {
        let stub = StubCloud(); stub.snapshot = snap()
        let file = url()
        let c = CloudInsights(cloud: stub, cacheURL: file)
        await c.refresh()
        stub.snapshot = nil
        await c.refresh()
        #expect(c.snapshot == nil)
        #expect(CloudInsights(cloud: StubCloud(), cacheURL: file).snapshot == nil)
    }

    @Test func offlineKeepsTheLastCopyAndSaysWhy() async {
        let stub = StubCloud(); stub.snapshot = snap()
        let c = CloudInsights(cloud: stub, cacheURL: url())
        await c.refresh()
        stub.fail = true
        await c.refresh()
        #expect(c.snapshot?.insights.streak == 3)
        #expect(c.status == .failed("You seem to be offline."))
    }

    @Test func noAccountOrABuildWithoutICloudIsPlainAndHarmless() async {
        let stub = StubCloud(); stub.answer = .unavailable("This build of Hushd is not set up for iCloud yet.")
        let c = CloudInsights(cloud: stub, cacheURL: url())
        await c.refresh()
        #expect(c.status == .unavailable("This build of Hushd is not set up for iCloud yet."))
        #expect(c.snapshot == nil)
    }

    @Test func iCloudNumbersFromAnotherDayClaimNoTimeForToday() {
        let old = snap(Date().addingTimeInterval(-3 * 86_400))
        #expect(old.shown().todayOnTaskSeconds == 0)
        #expect(snap().shown().todayOnTaskSeconds == 600)
    }
}
