import XCTest
import FocusJudge
@testable import FocusUI

@MainActor
final class UpdateTests: XCTestCase {
    var root: URL!
    override func setUp() { root = FileManager.default.temporaryDirectory.appendingPathComponent("focus-update-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    /// A fake bundle: Info.plist with a build ID, an executable, and a plist modified `age` seconds ago.
    @discardableResult func bundle(_ name: String, id: String?, age: Double = 60, executable: Bool = true) throws -> URL {
        let app = root.appendingPathComponent(name)
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleName": "Hushd"]
        if let id { plist["FocusBuildID"] = id }
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: plistURL.path)
        if executable {
            let exe = macos.appendingPathComponent("focus-app")
            try Data("#!/bin/sh\n".utf8).write(to: exe)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        }
        return app
    }

    func testANewerFinishedBuildIsOffered() throws {
        let own = try bundle("Installed.app", id: "20261013100000-aaaa"), src = try bundle("Source.app", id: "20261013120000-bbbb")
        let o = UpdateCheck.offer(ownID: "20261013100000-aaaa", ownApp: own, sourceApp: src)
        XCTAssertEqual(o?.buildID, "20261013120000-bbbb")
    }

    func testSameOrOlderBuildIsNotOffered() throws {
        let own = try bundle("Installed.app", id: "20261013120000-bbbb")
        XCTAssertNil(UpdateCheck.offer(ownID: "20261013120000-bbbb", ownApp: own, sourceApp: try bundle("Same.app", id: "20261013120000-bbbb")))
        XCTAssertNil(UpdateCheck.offer(ownID: "20261013120000-bbbb", ownApp: own, sourceApp: try bundle("Old.app", id: "20261012090000-cccc")))
    }

    func testACopyWithoutAnIDTakesAnyStampedBuild() throws {
        let own = try bundle("Installed.app", id: nil), src = try bundle("Source.app", id: "20261013120000-bbbb")
        XCTAssertNotNil(UpdateCheck.offer(ownID: nil, ownApp: own, sourceApp: src))
    }

    func testABuildStillBeingWrittenIsLeftAlone() throws {
        let own = try bundle("Installed.app", id: "20261013100000-aaaa")
        XCTAssertNil(UpdateCheck.offer(ownID: "20261013100000-aaaa", ownApp: own, sourceApp: try bundle("Fresh.app", id: "20261013120000-bbbb", age: 3)), "modified 3 s ago: the build script may still be signing it")
        XCTAssertNil(UpdateCheck.offer(ownID: "20261013100000-aaaa", ownApp: own, sourceApp: try bundle("NoExe.app", id: "20261013120000-bbbb", executable: false)))
    }

    func testMissingOrUnstampedSourceIsIgnoredAndNeverOffersItself() throws {
        let own = try bundle("Installed.app", id: "20261013100000-aaaa")
        XCTAssertNil(UpdateCheck.offer(ownID: "20261013100000-aaaa", ownApp: own, sourceApp: root.appendingPathComponent("Nowhere.app")))
        XCTAssertNil(UpdateCheck.offer(ownID: "20261013100000-aaaa", ownApp: own, sourceApp: try bundle("Plain.app", id: nil)))
        XCTAssertNil(UpdateCheck.offer(ownID: "20260101000000-old", ownApp: own, sourceApp: own), "the running bundle is never its own update")
    }

    // MARK: controller rules
    func controller() -> SessionController { SessionController(judge: CountingJudge { _ in Verdict(label: .onTask) }, prefs: noWords(), now: { 0 }) }
    let offer = UpdateOffer(buildID: "20261013120000-bbbb", sourcePath: "/tmp/Hushd.app")

    func testOfferShowsBetweenSessionsAndInstallRunsTheHook() {
        let c = controller(); var installed: UpdateOffer?
        c.onInstallUpdate = { installed = $0 }
        XCTAssertNil(c.visibleUpdate)
        c.setUpdateOffer(offer)
        XCTAssertEqual(c.visibleUpdate, offer)
        c.installUpdate()
        XCTAssertEqual(installed, offer)
    }

    func testNothingIsOfferedOrInstalledDuringASession() {
        let c = controller(); var installed = false
        c.onInstallUpdate = { _ in installed = true }
        c.setUpdateOffer(offer)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        XCTAssertNil(c.visibleUpdate)
        c.installUpdate()
        XCTAssertFalse(installed, "a restart would end the session")
    }

    func testLaterHidesThatBuildButANewerOneComesBack() {
        let c = controller()
        c.setUpdateOffer(offer); c.dismissUpdate()
        XCTAssertNil(c.visibleUpdate)
        c.setUpdateOffer(UpdateOffer(buildID: "20261013130000-dddd", sourcePath: offer.sourcePath))
        XCTAssertNotNil(c.visibleUpdate)
    }

    func testTurningUpdatesOffHidesTheOffer() {
        let c = controller()
        c.setUpdateOffer(offer); c.prefs.offerUpdates = false
        XCTAssertNil(c.visibleUpdate)
    }
}
