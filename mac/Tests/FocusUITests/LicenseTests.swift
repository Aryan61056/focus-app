import XCTest
@testable import FocusUI

/// The license: key typing, activation, the daily check, offline grace, revoke, and that a busy server never locks anyone out.
@MainActor
final class LicenseTests: XCTestCase {
    let info = LicenseInfo(plan: "beta", expiresAt: nil, maxActivations: 2, activations: 1, keyHint: "ABCD")
    let good = "HUSHD-ABCDE-FGHJK-MNPQR-STVWX-YZ234"
    var dirs: [URL] = []
    override func tearDown() { dirs.forEach { try? FileManager.default.removeItem(at: $0) }; dirs = [] }
    func vault() -> LicenseVault {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("hushd-lic-\(UUID().uuidString)", isDirectory: true)
        dirs.append(u); return LicenseVault(url: u.appendingPathComponent("license.json"))
    }

    /// A transport that answers from a script and remembers what it was asked.
    final class Script: @unchecked Sendable {
        var replies: [LicenseReply] = []
        var calls: [(LicenseCall, String)] = []
        lazy var transport: LicenseTransport = { [unowned self] call, key in
            self.calls.append((call, key)); return self.replies.isEmpty ? .unreachable : self.replies.removeFirst()
        }
    }

    // MARK: typing

    func testKeyFormatsWhileTyping() {
        XCTAssertEqual(LicenseKey.format(""), "")
        XCTAssertEqual(LicenseKey.format("hushd"), "HUSHD-")
        XCTAssertEqual(LicenseKey.format("abc"), "HUSHD-ABC")
        XCTAssertEqual(LicenseKey.format("abcdefg"), "HUSHD-ABCDE-FG")
        XCTAssertEqual(LicenseKey.format(" hushd abcde-fghjk mnpqr stvwx yz234 "), good)
        XCTAssertEqual(LicenseKey.format(good + "EXTRA"), good)
        XCTAssertTrue(LicenseKey.isComplete(good))
        XCTAssertFalse(LicenseKey.isComplete("HUSHD-ABCDE"))
    }

    // MARK: activating

    func testActivateKeepsTheKeyAndAsksToContinue() async {
        let s = Script(); s.replies = [.ok(info)]
        let v = vault()
        let c = LicenseCenter(transport: s.transport, vault: v, enforced: true)
        XCTAssertTrue(c.needsLicense)
        let ok = await c.activate("hushd abcde fghjk mnpqr stvwx yz234")
        XCTAssertTrue(ok)
        XCTAssertEqual(s.calls.first?.1, good)
        XCTAssertEqual(c.status, .active(info))
        XCTAssertTrue(c.needsLicense, "the success state stays up until Continue")
        c.acknowledge()
        XCTAssertFalse(c.needsLicense)
        // A relaunch finds it on disk.
        let again = LicenseCenter(transport: Script().transport, vault: v, enforced: true)
        XCTAssertTrue(again.allowsUse)
        XCTAssertEqual(again.keyHint, "ABCD")
    }

    func testActivateRefusalsSayWhy() async {
        let s = Script(); s.replies = [.refused(.invalidKey, nil), .refused(.activationLimit, info), .unreachable]
        let c = LicenseCenter(transport: s.transport, vault: vault(), enforced: true)
        let a = await c.activate(good); XCTAssertFalse(a); XCTAssertEqual(c.error, LicenseRefusal.invalidKey.message)
        let b = await c.activate(good); XCTAssertFalse(b); XCTAssertEqual(c.error, LicenseRefusal.activationLimit.message)
        let d = await c.activate(good); XCTAssertFalse(d); XCTAssertTrue(c.error?.contains("internet") ?? false)
        XCTAssertEqual(c.status, .unlicensed)
    }

    func testShortKeyIsNotSent() async {
        let s = Script()
        let c = LicenseCenter(transport: s.transport, vault: vault(), enforced: true)
        let ok = await c.activate("HUSHD-ABC")
        XCTAssertFalse(ok); XCTAssertTrue(s.calls.isEmpty); XCTAssertNotNil(c.error)
    }

    // MARK: staying valid

    func testRefreshRevokedBlocksButBusyServerDoesNot() async {
        let s = Script(); s.replies = [.ok(info), .refused(.serverError, nil), .refused(.revoked, info)]
        let c = LicenseCenter(transport: s.transport, vault: vault(), enforced: true)
        _ = await c.activate(good); c.acknowledge()
        await c.refresh()
        XCTAssertTrue(c.allowsUse, "a busy server never locks anyone out")
        await c.refresh()
        XCTAssertEqual(c.status, .blocked(.revoked, info))
        XCTAssertTrue(c.needsLicense)
    }

    func testOfflineKeepsWorkingForTwoWeeksThenStops() async {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let s = Script(); s.replies = [.ok(info)]
        let c = LicenseCenter(transport: s.transport, vault: vault(), enforced: true, now: { clock })
        _ = await c.activate(good); c.acknowledge()
        clock.addTimeInterval(3 * 86400 + 60)
        await c.refresh()   // unreachable
        if case .offline(_, let left) = c.status { XCTAssertEqual(left, 11) } else { XCTFail("\(c.status)") }
        XCTAssertTrue(c.allowsUse)
        clock.addTimeInterval(12 * 86400)
        await c.refresh()
        XCTAssertEqual(c.status, .blocked(.offlineTooLong, info))
        XCTAssertFalse(c.allowsUse)
    }

    func testRelaunchedAfterLongOfflineIsBlockedWithoutAsking() {
        let v = vault()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        v.save(LicenseRecord(key: good, info: info, validatedAt: t0))
        let c = LicenseCenter(transport: Script().transport, vault: v, enforced: true, now: { t0.addingTimeInterval(20 * 86400) })
        XCTAssertEqual(c.status, .blocked(.offlineTooLong, info))
    }

    func testRefreshIfDueWaitsADay() async {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let s = Script(); s.replies = [.ok(info), .ok(info)]
        let c = LicenseCenter(transport: s.transport, vault: vault(), enforced: true, now: { clock })
        _ = await c.activate(good)
        await c.refreshIfDue(); XCTAssertEqual(s.calls.count, 1)
        clock.addTimeInterval(25 * 3600)
        await c.refreshIfDue(); XCTAssertEqual(s.calls.count, 2)
    }

    // MARK: leaving

    func testDeactivateFreesTheKeyOnlyWhenTheServerAgrees() async {
        let s = Script(); s.replies = [.ok(info), .unreachable, .ok(info)]
        let v = vault()
        let c = LicenseCenter(transport: s.transport, vault: v, enforced: true)
        _ = await c.activate(good)
        let offline = await c.deactivate()
        XCTAssertFalse(offline); XCTAssertNotNil(v.load(), "offline keeps the key, so the place isn't lost")
        let done = await c.deactivate()
        XCTAssertTrue(done); XCTAssertNil(v.load()); XCTAssertEqual(c.status, .unlicensed)
    }

    // MARK: not enforced, and the file

    func testDevBuildsAreNotLockedButStillShowStatus() {
        let c = LicenseCenter(transport: Script().transport, vault: vault(), enforced: false)
        XCTAssertFalse(c.needsLicense); XCTAssertEqual(c.status, .unlicensed)
    }

    func testVaultFileIsPrivate() throws {
        let v = vault()
        v.save(LicenseRecord(key: good, info: info, validatedAt: Date()))
        let attrs = try FileManager.default.attributesOfItem(atPath: v.url!.path)
        XCTAssertEqual((attrs[.posixPermissions] as? Int) ?? 0, 0o600)
        XCTAssertEqual(v.load()?.key, good)
    }
}
