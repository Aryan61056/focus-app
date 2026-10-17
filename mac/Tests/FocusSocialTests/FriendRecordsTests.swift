import XCTest
import CloudKit
@testable import FocusSocial
@testable import FocusUI

/// The record mapping only: nothing here talks to iCloud, which needs a signed build (docs/SOCIAL.md).
final class FriendRecordsTests: XCTestCase {
    let zone = CKRecordZone.ID(zoneName: "Friends", ownerName: "_owner")
    let card = FriendCard(id: "me", name: "Ari", days: [ShareDay(day: "2026-10-16", focusedSeconds: 2_700, slips: 1, sessions: 1)],
                          streak: 4, updated: Date(timeIntervalSince1970: 1_800_000_000), emoji: "\u{1F43C}")

    func testACardSurvivesTheTripAndCarriesOnlyNumbers() throws {
        let r = try FriendRecords.card(card, zone: zone)
        XCTAssertEqual(r.recordType, "FocusCard")
        for key in ["name", "days", "streak", "emoji"] { XCTAssertNil(r[key], "\(key) is only in encryptedValues, so iCloud cannot read it") }
        let back = try XCTUnwrap(FriendRecords.decodeCard(r, owner: "_owner", updated: card.updated))
        XCTAssertEqual(back.id, "_owner", "the friend is identified by whose zone it came from, not by what the record says")
        XCTAssertEqual(back.name, "Ari"); XCTAssertEqual(back.streak, 4); XCTAssertEqual(back.emoji, "\u{1F43C}")
        XCTAssertEqual(back.days, card.days)
    }

    func testAHandMadeCardCannotFillThePage() throws {
        var big = card
        big.name = String(repeating: "x", count: 500); big.streak = 9_999_999
        big.days = (0..<400).map { ShareDay(day: "d\($0)", focusedSeconds: 1, slips: 0, sessions: 1) }
        big.emoji = "\u{1F4A9}"
        let back = try XCTUnwrap(FriendRecords.decodeCard(FriendRecords.card(big, zone: zone), owner: "_o"))
        XCTAssertEqual(back.name.count, 40)
        XCTAssertEqual(back.days.count, FriendCard.daysKept)
        XCTAssertEqual(back.streak, 100_000)
        XCTAssertNil(back.emoji, "only the fixed avatars are shown")
    }

    func testACardRecordWithTheWrongNameOrTypeIsIgnored() throws {
        let other = CKRecord(recordType: "FocusCard", recordID: CKRecord.ID(recordName: "second", zoneID: zone))
        other.encryptedValues["name"] = "Fake"
        XCTAssertNil(FriendRecords.decodeCard(other, owner: "_o"))
        let cheer = FriendRecords.cheer(.fire, to: "me", zone: zone)
        XCTAssertNil(FriendRecords.decodeCard(cheer, owner: "_o"))
    }

    func testACheerReachesOnlyItsAddressee() {
        let r = FriendRecords.cheer(.keepGoing, to: "me", zone: zone)
        let now = Date()
        let c = FriendRecords.decodeCheer(r, owner: "_o", me: "me", cutoff: now.addingTimeInterval(-60), at: now)
        XCTAssertEqual(c?.kind, .keepGoing); XCTAssertEqual(c?.from, "_o")
        XCTAssertNil(FriendRecords.decodeCheer(r, owner: "_o", me: "someone-else", cutoff: now.addingTimeInterval(-60), at: now))
        XCTAssertNil(FriendRecords.decodeCheer(r, owner: "_o", me: nil, cutoff: now.addingTimeInterval(-60), at: now))
    }

    func testOldCheersAndUnknownKindsAreDropped() {
        let now = Date()
        let r = FriendRecords.cheer(.fire, to: "me", zone: zone)
        XCTAssertNil(FriendRecords.decodeCheer(r, owner: "_o", me: "me", cutoff: now, at: now.addingTimeInterval(-3_600)))
        r.encryptedValues["kind"] = "free-text-from-a-stranger"
        XCTAssertNil(FriendRecords.decodeCheer(r, owner: "_o", me: "me", cutoff: now.addingTimeInterval(-60), at: now))
    }

    @MainActor func testErrorsBecomePlainSentences() {
        let offline = CKError(.networkUnavailable)
        XCTAssertTrue(CloudKitFriends.say(offline).contains("offline"))
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: ["x": CKError(.quotaExceeded)]])
        XCTAssertEqual(CloudKitFriends.say(partial), "Your iCloud storage is full.")
        XCTAssertEqual(CloudKitFriends.say(CKError(.internalError)), "Could not reach iCloud. Try again in a moment.")
    }

    @MainActor func testAnUnsignedBuildSaysSoInsteadOfTouchingICloud() async {
        guard !CloudKitFriends.entitled else { return }
        let availability = await CloudKitFriends().availability()
        guard case .unavailable = availability else { return XCTFail("expected unavailable, got \(availability)") }
    }
}
