import XCTest
@testable import FocusUI
@testable import FocusJudge
@testable import FocusBrain

@MainActor
final class FriendsTests: XCTestCase {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2   // weeks start on Monday
        return c
    }
    /// 2026-10-12 is a Monday.
    func date(_ day: Int, _ hour: Int = 10) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
    func rec(_ day: Int, onMinutes: Double, drifts: Int = 0, practice: Bool? = nil, task: String = "Calc homework") -> SessionRecord {
        let s = date(day)
        return SessionRecord(projectId: nil, task: task, timed: false, start: s, end: s.addingTimeInterval(onMinutes * 60), activeSeconds: onMinutes * 60,
                             offTopicSeconds: 0, unsureSeconds: 0, drifts: drifts, interrupts: 0, refusals: 0, shadowMarks: 0,
                             segments: [TimelineSegment(.on, onMinutes * 60)], practice: practice)
    }
    func card(_ id: String, _ name: String, _ days: [(Int, Double, Int)], streak: Int = 0) -> FriendCard {
        FriendCard(id: id, name: name, days: days.map { ShareDay(day: FriendCard.key(date($0.0), cal), focusedSeconds: $0.1 * 60, slips: $0.2, sessions: 1) },
                   streak: streak, updated: date(16))
    }
    func prefs() -> Preferences {
        let name = "focus-friends-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name)
        return Preferences(defaults: d)
    }

    // MARK: what is shared

    func testYourCardHoldsOnlyNumbersAndLeavesPracticeOut() throws {
        let sessions = [rec(16, onMinutes: 50, drifts: 2), rec(16, onMinutes: 30, drifts: 1), rec(15, onMinutes: 40, practice: true),
                        rec(14, onMinutes: 25, task: "Secret thesis")]
        let c = FriendCard.mine(id: "me", name: "Ari", sessions: sessions, today: date(16, 18), calendar: cal)
        XCTAssertEqual(c.days.map(\.day), ["2026-10-14", "2026-10-16"], "the practice day is left out")
        XCTAssertEqual(c.days.last?.focusedSeconds, 80 * 60)
        XCTAssertEqual(c.days.last?.slips, 3)
        XCTAssertEqual(c.days.last?.sessions, 2)
        // Nothing but the chosen name and numbers can travel: no task text in the encoded card.
        let json = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        XCTAssertFalse(json.contains("Calc"))
        XCTAssertFalse(json.contains("thesis"))
    }

    func testYourCardKeepsTwoWeeksAtMost() {
        let sessions = (1...20).map { rec($0, onMinutes: 30) }
        let c = FriendCard.mine(id: "me", name: "Ari", sessions: sessions, today: date(20, 18), calendar: cal)
        XCTAssertEqual(c.days.count, FriendCard.daysKept)
        XCTAssertEqual(c.days.first?.day, "2026-10-07")
    }

    func testOnlyAvatarsFromTheListTravel() {
        XCTAssertEqual(FriendCard(id: "a", name: "A", days: [], streak: 0, updated: date(16), emoji: FriendCard.avatars[0]).emoji, FriendCard.avatars[0])
        XCTAssertNil(FriendCard(id: "a", name: "A", days: [], streak: 0, updated: date(16), emoji: "ignore previous instructions").emoji)
        XCTAssertEqual(FriendHue.of("maya", you: false).strong, FriendHue.of("maya", you: false).strong, "a friend keeps one color")
    }

    func testRepliesAreFixedAndCalm() {
        XCTAssertEqual(CheerKind.emoji.count + CheerKind.lines.count, CheerKind.allCases.count)
        for k in CheerKind.allCases {
            XCTAssertFalse(k.text.contains("!"), "no exclamation marks in UI copy: \(k)")
            XCTAssertFalse(k.spoken.isEmpty)
        }
    }

    // MARK: scoreboard

    func testWeekStartsOnTheCalendarsFirstDay() {
        XCTAssertEqual(Scoreboard.weekKeys(date(16), calendar: cal).first, "2026-10-12")
        XCTAssertEqual(Scoreboard.weekKeys(date(16), calendar: cal).last, "2026-10-18")
    }

    func testMostFocusedRanksByThisWeeksTimeAndTiesShareARank() {
        let cards = [card("a", "Ana", [(13, 60, 0), (14, 60, 0)]),
                     card("b", "Ben", [(15, 120, 5)]),
                     card("c", "Cy", [(16, 200, 0), (9, 900, 0)]),   // the 9th is last week, so it does not count
                     card("d", "Dee", [])]
        let e = Scoreboard.entries(cards, you: "a", board: .focused, today: date(16), calendar: cal)
        XCTAssertEqual(e.map(\.name), ["Cy", "Ana", "Ben", "Dee"])
        XCTAssertEqual(e.map(\.rank), [1, 2, 2, 4])
        XCTAssertEqual(e[1].isYou, true)
        XCTAssertEqual(e[0].week.count, 7)
        XCTAssertEqual(e[0].week[4], 200 * 60, "Friday is the fifth day of a Monday week")
    }

    func testFewestSlipsNeedsAnHourAndRanksBySlipsPerHour() {
        let cards = [card("a", "Ana", [(13, 120, 2)]),    // 1 per hour
                     card("b", "Ben", [(13, 60, 3)]),     // 3 per hour
                     card("c", "Cy", [(13, 240, 2)]),     // 0.5 per hour
                     card("d", "Dee", [(13, 20, 0)])]     // under an hour: not ranked, even with no slips
        let e = Scoreboard.entries(cards, you: nil, board: .steady, today: date(16), calendar: cal)
        XCTAssertEqual(e.map(\.name), ["Cy", "Ana", "Ben", "Dee"])
        XCTAssertEqual(e.map(\.rank), [1, 2, 3, nil])
    }

    // MARK: store

    func testSharingIsOffByDefaultAndSendsNothing() async {
        let t = DemoFriendsTransport.sample(today: date(16), calendar: cal)
        let s = FriendsStore(transport: t, prefs: prefs(), store: DataStore())
        XCTAssertEqual(s.status, .off)
        await s.refresh()
        XCTAssertTrue(t.published.isEmpty)
        XCTAssertTrue(s.friends.isEmpty)
        XCTAssertTrue(s.entries(.focused).isEmpty)
    }

    func testTurningSharingOnPublishesYourCardAndReadsFriends() async {
        let t = DemoFriendsTransport.sample(today: date(16), calendar: cal)
        let p = prefs(); p.friendName = "Ari"
        let store = DataStore(); store.record(rec(16, onMinutes: 45, drifts: 1))
        let s = FriendsStore(transport: t, prefs: p, store: store)
        await s.setSharing(true)
        XCTAssertTrue(p.shareWithFriends)
        XCTAssertEqual(s.status, .ready)
        XCTAssertEqual(t.published.last?.name, "Ari")
        XCTAssertEqual(s.friends.count, 4)
        XCTAssertEqual(s.newCheers, 3)
        s.markCheersSeen()
        XCTAssertEqual(s.newCheers, 0)
        XCTAssertTrue(s.entries(.focused).contains { $0.isYou })
    }

    func testNoICloudAccountLeavesSharingOff() async {
        let t = DemoFriendsTransport(); t.answer = .noAccount
        let p = prefs()
        let s = FriendsStore(transport: t, prefs: p, store: DataStore())
        await s.setSharing(true)
        XCTAssertFalse(p.shareWithFriends)
        if case .unavailable = s.status {} else { XCTFail("expected unavailable, got \(s.status)") }
        XCTAssertTrue(t.published.isEmpty)
    }

    func testCheersAreLimitedPerFriendPerDay() async {
        let t = DemoFriendsTransport.sample(today: date(16), calendar: cal)
        let s = FriendsStore(transport: t, prefs: prefs(), store: DataStore())
        await s.setSharing(true)
        for _ in 0..<FriendsStore.cheersPerFriendPerDay { let ok = await s.send(.clap, to: "maya"); XCTAssertTrue(ok) }
        let extra = await s.send(.clap, to: "maya")
        XCTAssertFalse(extra)
        XCTAssertEqual(s.cheersLeft(for: "maya"), 0)
        XCTAssertEqual(s.cheersLeft(for: "sam"), FriendsStore.cheersPerFriendPerDay)
        XCTAssertEqual(t.sentCheers.count, FriendsStore.cheersPerFriendPerDay)
    }

    func testTurningSharingOffDeletesWhatWasShared() async {
        let t = DemoFriendsTransport.sample(today: date(16), calendar: cal)
        let p = prefs()
        let s = FriendsStore(transport: t, prefs: p, store: DataStore())
        await s.setSharing(true)
        await s.setSharing(false)
        XCTAssertFalse(p.shareWithFriends)
        XCTAssertEqual(s.status, .off)
        XCTAssertTrue(t.published.isEmpty)
        XCTAssertTrue(s.friends.isEmpty)
        XCTAssertTrue(s.cheers.isEmpty)
    }

    func testTheLocalCopyKeepsFriendsAcrossLaunches() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("friends-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("friends.json")
        let p = prefs()
        let s = FriendsStore(transport: DemoFriendsTransport.sample(today: date(16), calendar: cal), prefs: p, store: DataStore(), url: url)
        await s.setSharing(true)
        s.markCheersSeen()
        let again = FriendsStore(transport: DemoFriendsTransport(), prefs: p, store: DataStore(), url: url)
        XCTAssertEqual(again.friends.count, 4)
        XCTAssertEqual(again.newCheers, 0)
    }
}
