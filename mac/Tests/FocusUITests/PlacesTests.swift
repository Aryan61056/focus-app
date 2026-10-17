import XCTest
@testable import FocusUI
import FocusJudge

/// Which place "Back to task" goes to, and that the controller sends you there (docs/STATUS.md, "Back to task goes to the place").
final class TaskPlacesTests: XCTestCase {
    func win(_ app: String, _ title: String, url: String = "", doc: String = "") -> WindowSnapshot { WindowSnapshot(app: app, title: title, url: url, documentPath: doc) }

    func testNothingRecordedMeansNowhereToGo() {
        XCTAssertNil(TaskPlaces().destination)
        XCTAssertTrue(TaskPlaces().candidates.isEmpty)
    }

    func testTheLastPlaceIsTheTaskOnceYouSettledThere() {
        var p = TaskPlaces()
        p.noteOnTask(win("Pages", "Essay"), at: 0); p.addDwell(win("Pages", "Essay"), seconds: 300)
        p.noteOnTask(win("Xcode", "App"), at: 400); p.addDwell(win("Xcode", "App"), seconds: 60)
        XCTAssertEqual(p.destination?.window.app, "Xcode", "you worked there for a minute, so that is where you were")
    }

    func testAGlanceDoesNotBecomeHome() {
        var p = TaskPlaces()
        p.noteOnTask(win("Pages", "Essay"), at: 0); p.addDwell(win("Pages", "Essay"), seconds: 300)
        p.noteOnTask(win("Safari", "Reference", url: "https://ref.example.com/a"), at: 310); p.addDwell(win("Safari", "Reference", url: "https://ref.example.com/a"), seconds: 8)
        XCTAssertEqual(p.destination?.window.app, "Pages", "ten seconds in a reference is a look, not the task")
        XCTAssertEqual(p.candidates.map(\.window.app), ["Pages", "Safari"])
        XCTAssertEqual(p.alternatives.map(\.window.app), ["Safari"])
    }

    func testWithNothingSettledItIsTheLatest() {
        var p = TaskPlaces()
        p.noteOnTask(win("Pages", "Essay"), at: 0); p.addDwell(win("Pages", "Essay"), seconds: 20)
        p.noteOnTask(win("Notes", "Plan"), at: 30); p.addDwell(win("Notes", "Plan"), seconds: 10)
        XCTAssertEqual(p.destination?.window.app, "Notes")
    }

    func testTheSameDocumentIsOnePlaceWhenItsTitleChanges() {
        var p = TaskPlaces()
        p.noteOnTask(win("Pages", "Essay", doc: "/Users/a/Essay.pages"), at: 0); p.addDwell(win("Pages", "Essay", doc: "/Users/a/Essay.pages"), seconds: 50)
        p.noteOnTask(win("Pages", "Essay \u{2014} Edited", doc: "/Users/a/Essay.pages"), at: 60)
        XCTAssertEqual(p.all.count, 1)
        XCTAssertEqual(p.all[0].dwell, 50, "the time in it stays with it")
        XCTAssertEqual(p.all[0].window.title, "Essay \u{2014} Edited", "and it remembers the title it has now")
    }

    func testTheSamePageIsOnePlaceWhateverItsQuery() {
        var p = TaskPlaces()
        p.noteOnTask(win("Safari", "Lecture", url: "https://notes.example.com/week3?x=1"), at: 0)
        p.noteOnTask(win("Safari", "Lecture", url: "https://notes.example.com/week3?x=2#top"), at: 5)
        XCTAssertEqual(p.all.count, 1)
        let other = win("Safari", "Lecture", url: "https://notes.example.com/week4")
        p.noteOnTask(other, at: 9)
        XCTAssertEqual(p.all.count, 2, "another page of the same site is another place")
    }

    func testTheShortestStayGoesFirstWhenThereIsNoRoom() {
        var p = TaskPlaces()
        for i in 0..<TaskPlaces.capacity { let w = win("App\(i)", "T\(i)"); p.noteOnTask(w, at: Double(i)); p.addDwell(w, seconds: i == 0 ? 500 : Double(10 + i)) }
        p.noteOnTask(win("New", "N"), at: 50)
        XCTAssertEqual(p.all.count, TaskPlaces.capacity)
        XCTAssertTrue(p.all.contains { $0.window.app == "App0" }, "the place you live in is never the one dropped")
        XCTAssertFalse(p.all.contains { $0.window.app == "App1" }, "the shortest stay is")
        XCTAssertEqual(p.all.first?.window.app, "New", "and the new place is the latest")
    }

    func testTimeInAWindowNeverReadAsOnTaskIsIgnored() {
        var p = TaskPlaces()
        p.addDwell(win("Slack", "General"), seconds: 100)
        XCTAssertTrue(p.all.isEmpty)
    }

    func testTheWordsOnScreenAreNeverKept() {
        var w = win("Notes", "Plan"); w.text = "private words"
        var p = TaskPlaces(); p.noteOnTask(w, at: 0)
        XCTAssertEqual(p.all[0].window.text, "")
    }

    func testNames() {
        XCTAssertEqual(TaskPlaces.pageTitle("Essay - Google Docs - Google Chrome", app: "Google Chrome"), "Essay - Google Docs")
        XCTAssertEqual(TaskPlaces.pageTitle("(3) Inbox - Safari", app: "Safari"), "Inbox")
        XCTAssertEqual(TaskPlaces.pageTitle("Notes", app: "Notes"), "Notes", "a title with no tail is left alone")
        XCTAssertEqual(TaskPlace(window: win("Pages", "Essay draft"), lastSeen: 0).label, "Pages \u{00B7} Essay draft")
        XCTAssertEqual(TaskPlace(window: win("Safari", "", url: "https://www.docs.example.com/x"), lastSeen: 0).label, "Safari \u{00B7} docs.example.com")
        XCTAssertEqual(TaskPlace(window: win("Pages", "", doc: "/Users/a/Essay.pages"), lastSeen: 0).label, "Pages \u{00B7} Essay.pages")
        XCTAssertEqual(TaskPlace(window: win("Pages", ""), lastSeen: 0).label, "Pages")
        XCTAssertLessThanOrEqual(TaskPlaces.shortName(win("Pages", String(repeating: "x", count: 80))).count, 28)
    }
}

@MainActor
final class BackToPlaceTests: XCTestCase {
    var t = 0.0
    var went: [(window: WindowSnapshot, allowTabs: Bool)] = []
    let judge = ScriptedJudge(markers: [("Notes", .on), ("Pages", .on), ("youtube", .off), ("Slack", .off)])

    let tabA = WindowSnapshot(app: "Safari", title: "Notes lecture", url: "https://notes.example.com/week3")
    let tabB = WindowSnapshot(app: "Safari", title: "youtube clip", url: "https://youtube.com/watch?v=1")
    let slack = WindowSnapshot(app: "Slack", title: "General")
    let pages = WindowSnapshot(app: "Pages", title: "Pages essay", documentPath: "/Users/a/Essay.pages")

    func make(_ outcome: @escaping (WindowSnapshot) -> ReturnOutcome = { _ in .exact }, configure: (SessionController) -> Void = { _ in }) -> SessionController {
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { [unowned self] in self.t })
        c.onGoToPlace = { [unowned self] w, tabs in went.append((w, tabs)); return outcome(w) }
        configure(c)
        return c
    }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }

    func testBackToTaskGoesToTheTabEvenWhenYouLeftTheBrowser() async {
        // The old route only found the tab when the distraction was another tab of the same browser. Here the browser was left sitting on
        // the video, and the next stop was another app.
        let c = make()
        c.windowChanged(tabA); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 60)
        c.windowChanged(tabB); await advance(c, to: 70)
        c.windowChanged(slack); await advance(c, to: 75)
        c.act(.backToTask)
        XCTAssertEqual(went.count, 1)
        XCTAssertEqual(went.first?.window.url, tabA.url, "the tab you were working in, not just Safari")
        XCTAssertEqual(went.first?.allowTabs, true)
        XCTAssertEqual(c.lastReturn?.outcome, .exact)
        XCTAssertEqual(c.lastReturn?.place.window.url, tabA.url)
    }

    func testAQuickLookDoesNotPullYouAwayFromTheWorkYouWereDoing() async {
        let c = make()
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 120)
        c.windowChanged(tabA); await advance(c, to: 128)
        c.windowChanged(tabB); await advance(c, to: 140)
        XCTAssertEqual(c.returnPlace?.window.app, "Pages")
        c.act(.backToTask)
        XCTAssertEqual(went.first?.window.documentPath, pages.documentPath)
        XCTAssertEqual(c.otherPlaces.map(\.window.app), ["Safari"], "and the menu offers the other place")
    }

    func testAPlaceYouStayedInIsWhereYouAreSent() async {
        let c = make()
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 60)
        c.windowChanged(tabA); await advance(c, to: 120)
        c.windowChanged(tabB); await advance(c, to: 130)
        c.act(.backToTask)
        XCTAssertEqual(went.first?.window.url, tabA.url)
    }

    func testTabsAreLeftAloneWhenThatIsSwitchedOffOrItIsPractice() async {
        let off = make(configure: { $0.prefs.switchTabs = false })
        off.windowChanged(tabA); off.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(off, to: 50); off.windowChanged(slack); await advance(off, to: 55)
        off.act(.backToTask)
        XCTAssertEqual(went.last?.allowTabs, false)

        went = []; t = 0
        let practice = make()
        practice.windowChanged(tabA); practice.begin(task: "Calc homework", preset: .standard, shadow: true)
        await advance(practice, to: 50); practice.windowChanged(slack); await advance(practice, to: 55)
        practice.act(.backToTask)
        XCTAssertEqual(went.last?.allowTabs, false, "practice sessions never steer a browser")
    }

    func testAPlaceThatCannotBeFoundFallsThroughToTheNext() async {
        let c = make({ $0.app == "Pages" ? .notFound : .appOnly })
        c.windowChanged(tabA); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 50)
        c.windowChanged(pages); await advance(c, to: 120)
        c.windowChanged(slack); await advance(c, to: 125)
        c.act(.backToTask)
        XCTAssertEqual(went.map(\.window.app), ["Pages", "Safari"], "the document's app was quit, so it tried the tab")
        XCTAssertEqual(c.lastReturn?.outcome, .appOnly)
        XCTAssertEqual(c.lastReturn?.place.window.app, "Safari")
    }

    func testNothingFoundIsReportedNotHidden() async {
        let c = make({ _ in .notFound })
        c.windowChanged(tabA); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 50); c.windowChanged(slack); await advance(c, to: 55)
        c.act(.backToTask)
        XCTAssertEqual(c.lastReturn?.outcome, .notFound)
    }

    func testBeingThereAlreadyDoesNothing() async {
        let c = make()
        c.windowChanged(tabA); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 60)
        c.act(.backToTask)
        XCTAssertTrue(went.isEmpty)
        XCTAssertEqual(c.lastReturn?.outcome, .alreadyThere)
    }

    func testGoingToAnotherPlaceFromTheMenu() async {
        let c = make()
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 120)
        c.windowChanged(tabA); await advance(c, to: 128)
        c.windowChanged(slack); await advance(c, to: 133)
        let other = c.otherPlaces.first
        XCTAssertEqual(other?.window.url, tabA.url)
        c.goTo(other!)
        XCTAssertEqual(went.last?.window.url, tabA.url)
    }

    func testPlacesAreDroppedWhenTheSessionEnds() async {
        let c = make()
        c.windowChanged(tabA); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 50)
        XCTAssertFalse(c.places.all.isEmpty)
        c.end(); await advance(c, to: 60)
        XCTAssertTrue(c.places.all.isEmpty)
        XCTAssertNil(c.lastReturn)
    }

    func testWithoutTheAppsHookTheOlderRouteStillBringsTheAppForward() async {
        var brought: [String] = [], switched: [String] = []
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { [unowned self] in self.t })
        c.onBringBackToApp = { brought.append($0) }
        c.onSwitchTab = { _, to in switched.append(to?.url ?? ""); return true }
        c.windowChanged(tabA); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 60)
        c.windowChanged(tabB); await advance(c, to: 70)
        c.act(.backToTask)
        XCTAssertEqual(brought.last, "Safari")
        XCTAssertEqual(switched, [tabA.url], "the same browser, another tab: it switches")
    }
}

final class TabTitleScriptTests: XCTestCase {
    func testSwitchByTitleUsesTheRightWordForEachBrowser() throws {
        XCTAssertTrue(try XCTUnwrap(TabScript.switchToTitle(app: "Safari", title: "Lecture notes - Safari")).contains("(name of t) contains \"Lecture notes\""))
        XCTAssertTrue(try XCTUnwrap(TabScript.switchToTitle(app: "Google Chrome", title: "Lecture notes - Google Chrome")).contains("(title of t) contains \"Lecture notes\""))
    }

    func testATitleTooShortToTrustOrABrowserWeDoNotSteerIsNil() {
        XCTAssertNil(TabScript.switchToTitle(app: "Safari", title: "Inbox"))
        XCTAssertNil(TabScript.switchToTitle(app: "Arc", title: "Lecture notes"))
    }

    func testAPageTitleCannotBecomeScript() throws {
        let s = try XCTUnwrap(TabScript.switchToTitle(app: "Safari", title: "x\"; do shell script \"rm -rf ~\" -- notes"))
        XCTAssertTrue(s.contains(#"contains "x\"; do shell script \"rm -rf ~\" -- notes""#), "every quote in the title is escaped, so it stays one piece of text")
    }
}
