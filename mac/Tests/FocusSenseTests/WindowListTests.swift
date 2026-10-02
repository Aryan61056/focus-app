import XCTest
@testable import FocusSense

final class WindowListTests: XCTestCase {
    func w(_ pid: Int32, _ layer: Int, _ name: String?) -> [String: Any] {
        var d: [String: Any] = [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer]
        if let name { d[kCGWindowName as String] = name }
        return d
    }

    func testPicksTheFrontMostTitledNormalWindowOfTheApp() {
        let list = [w(7, 25, "Menu bar item"), w(5, 0, "Other app"), w(7, 0, ""), w(7, 0, "Calc homework"), w(7, 0, "Older window")]
        XCTAssertEqual(AXWindowSource.title(inWindowList: list, pid: 7), "Calc homework")
        XCTAssertEqual(AXWindowSource.title(inWindowList: list, pid: 99), "")
        XCTAssertEqual(AXWindowSource.title(inWindowList: [w(7, 0, nil)], pid: 7), "")
    }
}
