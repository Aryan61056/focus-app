import XCTest
import CoreGraphics
import FocusJudge
@testable import FocusUI
@testable import FocusSense

/// Pausing means Hushd stops looking and stops acting (owner, 2026-10-15: "the app seems to keep working even when paused").
@MainActor
final class PauseTests: XCTestCase {
    var t = 0.0
    let notes = WindowSnapshot(app: "Notes", title: "Calc homework")
    let video = WindowSnapshot(app: "Safari", title: "Funny cats", url: "https://youtube.com/watch?v=1")

    static func prefs() -> Preferences {
        let p = Preferences(defaults: UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!)
        p.matchTaskWords = false; p.practiceRemoved = false; p.restartPractice(); p.checkRate = .normal; p.sensitivity = .careful; p.paceMatters = false
        return p
    }

    func make() -> SessionController {
        let c = SessionController(judge: ScriptedJudge(markers: [("Notes", .on), ("youtube", .off)]), prefs: Self.prefs(), now: { [unowned self] in self.t })
        c.windowChanged(notes)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        return c
    }

    func settle() async { for _ in 0..<8 { await Task.yield(); try? await Task.sleep(nanoseconds: 5_000_000) } }

    struct Grabber: ScreenGrabber {
        var isAllowed: Bool { true }
        func requestAccess() {}
        func grab() async -> (image: CGImage, app: String)? {
            let ctx = CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return (ctx.makeImage()!, "Notes")
        }
    }
    struct Reader: ScreenReader { func words(in image: CGImage) async -> String { "Problem 4. Integrate by parts." } }

    func testHeldCoversPauseBreakAndSnoozeButNotAPrivateWindow() {
        let c = make()
        XCTAssertTrue(c.isSensing); XCTAssertFalse(c.isHeld)
        c.act(.pause); XCTAssertTrue(c.isHeld); XCTAssertFalse(c.isSensing)
        c.act(.resume); XCTAssertTrue(c.isSensing)
        c.act(.breakTime, minutes: 5); XCTAssertTrue(c.isHeld)
        c.act(.resume)
        c.windowChanged(WindowSnapshot(app: "Browser", title: "Private browsing", url: "https://bank.example/login"))
        XCTAssertEqual(c.presence.reason, "sensitive"); XCTAssertFalse(c.isHeld, "a private window keeps the watcher on so Hushd knows when it ends")
    }

    func testNoPictureIsTakenWhilePausedAndItComesBackOnResume() async {
        let c = make(); c.prefs.readScreen = true
        let w = PreviewWatcher(grabber: Grabber(), reader: Reader(), controller: c)
        w.capture(); await settle(); XCTAssertNotNil(c.previewFrame)
        c.act(.pause)
        XCTAssertNil(c.previewFrame, "the picture is dropped at once")
        XCTAssertTrue(c.screenText.isEmpty)
        w.capture(); await settle(); XCTAssertNil(c.previewFrame, "and none is taken while paused")
        c.act(.resume)
        w.capture(); await settle(); XCTAssertNotNil(c.previewFrame)
    }

    func testTheWindowIsNotReadWhilePausedAndIsReadAgainOnResume() {
        let c = make()
        let src = FakeSource(); src.next = notes
        let sense = SenseCoordinator(source: src, controller: c)
        sense.sync()
        let before = src.reads
        XCTAssertGreaterThan(before, 0)
        c.act(.pause); sense.sync()
        t += 30
        let afterPause = src.reads
        sense.sync(); sense.sync()
        XCTAssertEqual(src.reads, afterPause, "no read of the window while paused")
        c.act(.resume); sense.sync()
        XCTAssertGreaterThan(src.reads, afterPause, "the first look comes at once when it resumes")
    }

    func testAWindowThatChangesWhilePausedIsNeitherRecordedNorJudged() {
        let c = make()
        let readings = c.readings.count
        c.act(.pause)
        c.windowChanged(video)
        XCTAssertEqual(c.readings.count, readings, "nothing is read while paused")
        XCTAssertEqual(c.stats.model, 0)
    }

    func testResumingLooksAtTheWindowAgain() async {
        let c = make()
        c.act(.pause)
        c.windowChanged(video)
        c.act(.resume)
        await c.waitForJudgments()
        XCTAssertEqual(c.currentWindow?.app, "Safari")
        XCTAssertTrue(c.readings.contains { $0.app == "Safari" }, "the window in front at resume is read")
    }

    func testNoCoverAndNoActionWhilePaused() {
        let c = make()
        c.blockedSites[Keys.site(video)] = "Safari"   // a site you were warned about earlier
        var hidden = 0
        c.onHideApp = { _ in hidden += 1 }
        c.act(.pause)
        c.windowChanged(video)
        for _ in 0..<120 { t += 1; c.tick() }
        XCTAssertNil(c.shield, "no cover while paused")
        XCTAssertEqual(hidden, 0, "no app is hidden while paused")
    }

    func testPausingTakesDownACoverThatWasUp() {
        let c = make()
        c.blockedSites[Keys.site(video)] = "Safari"
        c.windowChanged(video)
        XCTAssertNotNil(c.shield, "the site you drifted into earlier is covered")
        c.act(.pause)
        XCTAssertNil(c.shield, "pausing lifts it")
        for _ in 0..<60 { t += 1; c.tick() }
        XCTAssertNil(c.shield)
    }

    func testNoGrayWhilePaused() {
        let c = make()
        c.prefs.screenGrayscale = true
        c.windowChanged(video)
        for _ in 0..<40 { t += 1; c.tick() }
        c.act(.pause)
        XCTAssertEqual(c.veilLevel(), 0, accuracy: 0.001)
    }
}
