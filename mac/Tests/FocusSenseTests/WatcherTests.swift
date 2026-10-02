import XCTest
import FocusJudge
import FocusUI
@testable import FocusSense

final class FakeSource: WindowSource {
    var next: WindowSnapshot?
    var isTrusted = true
    var reads = 0
    func current() -> WindowSnapshot? { reads += 1; return next }
}

@MainActor
final class WatcherTests: XCTestCase {
    var t = 0.0
    func make() -> (SessionController, FakeSource, WindowWatcher) {
        let c = SessionController(judge: ScriptedJudge(markers: [("Notes", .on)]), now: { [unowned self] in self.t })
        let src = FakeSource()
        return (c, src, WindowWatcher(source: src, controller: c))
    }

    func testPassesChangesOnAndIgnoresRepeats() {
        let (c, src, w) = make()
        c.begin(task: "Calc homework", shadow: false)
        src.next = WindowSnapshot(app: "Notes", title: "Calc homework")
        w.poll(); w.poll(); w.poll()
        XCTAssertEqual(c.currentWindow?.app, "Notes")
        src.next = WindowSnapshot(app: "Safari", title: "Docs")
        w.poll()
        XCTAssertEqual(c.currentWindow?.app, "Safari")
    }

    func testNilKeepsThePreviousWindow() {
        let (c, src, w) = make()
        c.begin(task: "x", shadow: false)
        src.next = WindowSnapshot(app: "Notes", title: "a"); w.poll()
        src.next = nil; w.poll()   // Focus itself is in front
        XCTAssertEqual(c.currentWindow?.app, "Notes")
    }

    func testReportsWhetherAccessibilityIsAllowed() {
        let (c, src, w) = make()
        src.isTrusted = false; w.poll()
        XCTAssertEqual(c.windowAccess, .appNamesOnly)
        src.isTrusted = true; w.poll()
        XCTAssertEqual(c.windowAccess, .allowed)
    }

    func testNothingIsReadUntilStartAndNothingAfterStop() async {
        let (_, src, w) = make()
        XCTAssertEqual(src.reads, 0)
        w.start(interval: 0.05)
        XCTAssertTrue(w.isRunning)
        try? await Task.sleep(nanoseconds: 200_000_000)
        w.stop()
        let after = src.reads
        XCTAssertGreaterThan(after, 1)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(src.reads, after, "no reads once stopped")
    }

    func testCoordinatorFollowsTheSession() async {
        let (c, src, _) = make()
        let co = SenseCoordinator(source: src, controller: c)
        co.bind()
        XCTAssertEqual(src.reads, 0, "no session, no reads")
        c.begin(task: "x", shadow: false)
        co.sync()
        XCTAssertGreaterThan(src.reads, 0)
        c.end(); co.sync()
        let n = src.reads
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(src.reads, n)
    }
}

final class AddressTests: XCTestCase {
    func testDocumentAttributeBecomesPathOrUrl() {
        XCTAssertEqual(AXWindowSource.address("file:///Users/a/Docs/essay.pages").path, "/Users/a/Docs/essay.pages")
        XCTAssertEqual(AXWindowSource.address("https://example.com/p").url, "https://example.com/p")
        XCTAssertEqual(AXWindowSource.address("something else").url, "")
        XCTAssertEqual(AXWindowSource.address("").path, "")
    }
}
