import XCTest
@testable import FocusUI

/// The notch's file shelf keeps only file locations, in memory, and never more than its limit.
@MainActor
final class NotchTrayTests: XCTestCase {
    func testAddsFilesOnceKeepsOrderAndDropsTheOldestPastTheLimit() {
        let t = NotchTray()
        let a = URL(fileURLWithPath: "/tmp/a.txt"), b = URL(fileURLWithPath: "/tmp/b.pdf")
        t.add([a, b, a]); t.add([a])
        XCTAssertEqual(t.items.map(\.url), [a, b], "a file already on the shelf is not added twice")
        XCTAssertEqual(t.drops, 1, "a drop of nothing new is not a drop")
        t.add([URL(string: "https://example.com/x")!])
        XCTAssertEqual(t.items.count, 2, "only files on this Mac")
        t.add((0..<20).map { URL(fileURLWithPath: "/tmp/f\($0)") })
        XCTAssertEqual(t.items.count, NotchTray.limit)
        XCTAssertEqual(t.items.last?.url.lastPathComponent, "f19", "the newest stays, the oldest go")
        t.remove(t.items[0].id); XCTAssertEqual(t.items.count, NotchTray.limit - 1)
        t.removeAll(); XCTAssertTrue(t.items.isEmpty)
    }
}
