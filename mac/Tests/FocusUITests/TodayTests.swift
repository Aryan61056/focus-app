import XCTest
import SwiftUI
import FocusBrain
@testable import FocusUI

final class TodayDashboardTests: XCTestCase {
    func testGreetingFollowsTheHour() {
        XCTAssertEqual(DashHeader.greeting(hour: 7), "Good morning")
        XCTAssertEqual(DashHeader.greeting(hour: 12), "Good afternoon")
        XCTAssertEqual(DashHeader.greeting(hour: 17), "Good evening")
        XCTAssertEqual(DashHeader.greeting(hour: 23), "Working late")
        XCTAssertEqual(DashHeader.greeting(hour: 3), "Working late")
    }

    func testReturnStartsTheTypedTaskOrContinuesTheLastProject() {
        let last = Project(name: "Calc homework")
        XCTAssertEqual(StartCard.plan(text: "Essay on sleep", timed: false, minutes: 50, last: last)?.task, "Essay on sleep")
        XCTAssertNil(StartCard.plan(text: "Essay on sleep", timed: false, minutes: 50, last: last)?.projectId)
        let again = StartCard.plan(text: "   ", timed: false, minutes: 50, last: last)
        XCTAssertEqual(again?.task, "Calc homework"); XCTAssertEqual(again?.projectId, last.id)
        XCTAssertNil(StartCard.plan(text: "", timed: false, minutes: 50, last: nil), "nothing to start")
    }

    func testATrailingNumberOrTheTimedChipMakesItTimed() {
        let typed = StartCard.plan(text: "Calc homework 25", timed: false, minutes: 50, last: nil)
        XCTAssertEqual(typed?.task, "Calc homework"); XCTAssertEqual(typed?.mode, .timed); XCTAssertEqual(typed?.duration, 25 * 60)
        let chip = StartCard.plan(text: "Calc homework", timed: true, minutes: 90, last: nil)
        XCTAssertEqual(chip?.mode, .timed); XCTAssertEqual(chip?.duration, 90 * 60)
        XCTAssertEqual(StartCard.plan(text: "Calc homework", timed: false, minutes: 90, last: nil)?.mode, .open)
    }

    @MainActor func testOnlyOneNoticeShowsAtATimeWithTheMostPressingFirst() {
        let c = SessionController(judge: ScriptedJudge(markers: []), now: { 0 })
        c.setWindowAccess(.appNamesOnly)
        let show = Binding.constant(false)
        XCTAssertNotNil(TodayView(c: c, showStart: show).notice, "access is asked for")
        c.setWindowAccess(.allowed)
        XCTAssertNil(TodayView(c: c, showStart: show).notice, "nothing else needs saying")
    }
}
