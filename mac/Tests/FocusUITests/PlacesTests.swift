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
    var reopens: [Bool] = []
    let judge = ScriptedJudge(markers: [("Notes", .on), ("Pages", .on), ("youtube", .off), ("Slack", .off)])

    let tabA = WindowSnapshot(app: "Safari", title: "Notes lecture", url: "https://notes.example.com/week3")
    let tabB = WindowSnapshot(app: "Safari", title: "youtube clip", url: "https://youtube.com/watch?v=1")
    let slack = WindowSnapshot(app: "Slack", title: "General")
    let pages = WindowSnapshot(app: "Pages", title: "Pages essay", documentPath: "/Users/a/Essay.pages")

    func make(_ outcome: @escaping (WindowSnapshot) -> ReturnOutcome = { _ in .exact }, configure: (SessionController) -> Void = { _ in }) -> SessionController {
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { [unowned self] in self.t })
        c.onGoToPlace = { [unowned self] w, tabs, reopen in went.append((w, tabs)); reopens.append(reopen); return outcome(w) }
        c.prefs.bringWorkingSet = false   // the older tests follow one place; the working set has its own tests below
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

final class PlacePositionTests: XCTestCase {
    func testScrollAndCursorAreKeptInRange() {
        let p = PlacePosition(scroll: 1.7, caret: -4, selection: -2, characters: -9)
        XCTAssertEqual(p.scroll, 1); XCTAssertEqual(p.caret, 0); XCTAssertEqual(p.selection, 0); XCTAssertEqual(p.characters, 0)
        XCTAssertEqual(PlacePosition(scroll: -3).scroll, 0)
    }

    func testAPositionWithNeitherIsEmpty() {
        XCTAssertTrue(PlacePosition().isEmpty)
        XCTAssertFalse(PlacePosition(scroll: 0).isEmpty, "the top of the page is a place")
        XCTAssertFalse(PlacePosition(caret: 0).isEmpty)
    }

    func testTheCursorIsPutBackOnlyWhereItStillMeansTheSame() {
        let p = PlacePosition(scroll: 0.5, caret: 120, selection: 10, characters: 1000)
        XCTAssertEqual(p.caretToRestore(nowCharacters: 1000)?.location, 120)
        XCTAssertEqual(p.caretToRestore(nowCharacters: 1030)?.location, 120, "a few more words does not move the paragraph")
        XCTAssertNil(p.caretToRestore(nowCharacters: 400), "the text changed so much that offset 120 is somewhere else now")
        XCTAssertNil(PlacePosition(caret: 900, characters: 1000).caretToRestore(nowCharacters: 880), "the text is now shorter than the cursor offset")
        XCTAssertEqual(PlacePosition(caret: 95, selection: 50, characters: 100).caretToRestore(nowCharacters: 100)?.length, 5, "the selection never runs past the end")
        XCTAssertNil(PlacePosition(scroll: 0.3).caretToRestore(nowCharacters: 100), "no cursor was noted")
    }

    func testScrollingIsSkippedWhenNothingWouldMove() {
        let p = PlacePosition(scroll: 0.5)
        XCTAssertTrue(p.scrollIsNear(0.505)); XCTAssertFalse(p.scrollIsNear(0.6))
    }
}

final class PlaceMemoryTests: XCTestCase {
    func win(_ app: String, _ title: String, url: String = "", doc: String = "") -> WindowSnapshot { WindowSnapshot(app: app, title: title, url: url, documentPath: doc) }

    func testWhereYouWereIsKeptWithThePlaceAndSurvivesSeeingItAgain() {
        var p = TaskPlaces()
        let essay = win("Pages", "Essay", doc: "/Users/a/Essay.pages")
        p.noteOnTask(essay, at: 0)
        p.notePosition(essay, PlacePosition(scroll: 0.4, caret: 50, characters: 800))
        p.noteOnTask(win("Pages", "Essay - Edited", doc: "/Users/a/Essay.pages"), at: 30)
        XCTAssertEqual(p.all.first?.position?.scroll, 0.4, "the same file under a new title is the same place, with the same spot")
    }

    func testAnEmptyReadingNeverErasesAGoodOneAndAnUnknownWindowIsIgnored() {
        var p = TaskPlaces()
        let essay = win("Pages", "Essay")
        p.noteOnTask(essay, at: 0)
        p.notePosition(essay, PlacePosition(scroll: 0.7))
        p.notePosition(essay, nil); p.notePosition(essay, PlacePosition())
        XCTAssertEqual(p.all.first?.position?.scroll, 0.7)
        p.notePosition(win("Slack", "General"), PlacePosition(scroll: 0.2))
        XCTAssertEqual(p.all.count, 1, "a window that was never on task does not become a place")
    }

    func testTheOtherWindowsOfTheTaskAreTheSettledOnesOldestFirstAtMostTwo() {
        var p = TaskPlaces()
        let names = ["A", "B", "C", "D"]
        for (i, n) in names.enumerated() { p.noteOnTask(win("App\(n)", "Window \(n)"), at: Double(i * 100)); p.addDwell(win("App\(n)", "Window \(n)"), seconds: 120) }
        p.noteOnTask(win("AppG", "Glance"), at: 450); p.addDwell(win("AppG", "Glance"), seconds: 5)
        let dest = p.destination!
        XCTAssertEqual(dest.window.app, "AppD", "the last one you settled in")
        let others = p.companions(of: dest)
        XCTAssertEqual(others.count, 2)
        XCTAssertFalse(others.contains { $0.id == dest.id }, "the main place is not its own companion")
        XCTAssertFalse(others.contains { $0.window.app == "AppG" }, "a glance is not part of the working set")
        XCTAssertEqual(others.map(\.lastSeen), others.map(\.lastSeen).sorted(), "oldest first, so the main place is raised last")
    }

    func testWindowsMatchAfterATitleChangeOrBeforeTheBrowserAddressIsRead() {
        XCTAssertTrue(LandingCheck.sameSpot(win("Pages", "Essay - Edited", doc: "/a/Essay.pages"), win("Pages", "Essay", doc: "/a/Essay.pages")))
        XCTAssertTrue(LandingCheck.sameSpot(win("Safari", "Lecture notes - Safari"), win("Safari", "Lecture notes", url: "https://n.example.com/w3")), "no address yet, same page title")
        XCTAssertFalse(LandingCheck.sameSpot(win("Safari", "Lecture notes"), win("Safari", "Other thing", url: "https://x.example.com/")))
        XCTAssertFalse(LandingCheck.sameSpot(win("Pages", "Essay"), win("Notes", "Essay")), "another app is never the same spot")
    }

    func testAReopenedPlaceIsRungLikeAnExactOne() {
        XCTAssertEqual(Landing.style(for: .reopened), .exact)
    }
}

final class ReopenPolicyTests: XCTestCase {
    func file(_ path: String, exists: Bool = true, runs: Bool = false) -> URL? {
        ReopenPolicy.fileURL(documentPath: path, exists: { _ in exists }, isExecutable: { _ in runs })
    }

    func testDocumentsAndFoldersMayBeOpened() {
        XCTAssertEqual(file("/Users/a/Essay.pages")?.path, "/Users/a/Essay.pages")
        XCTAssertEqual(file("/Users/a/Projects/Focus App")?.path, "/Users/a/Projects/Focus App", "a Finder window or an editor's project folder")
        XCTAssertEqual(file("/Users/a/notes.TXT")?.lastPathComponent, "notes.TXT")
    }

    func testAnythingThatRunsOrIsGoneIsNeverOpened() {
        XCTAssertNil(file("/Users/a/Essay.pages", exists: false), "the file was deleted")
        for bad in ["/Applications/Sketchy.app", "/Users/a/run.command", "/Users/a/x.sh", "/Users/a/inst.pkg", "/Users/a/x.dmg", "/Users/a/a.scpt", "/Users/a/Evil.webloc", "/Users/a/x.py", "/Users/a/x.JAR"] {
            XCTAssertNil(file(bad), bad)
        }
        XCTAssertNil(file("/Users/a/tool", runs: true), "a plain file with the execute bit is a program")
    }

    func testOnlyAbsolutePathsWithoutTricks() {
        XCTAssertNil(file("Essay.pages")); XCTAssertNil(file("~/Essay.pages")); XCTAssertNil(file("")); XCTAssertNil(file("/Users/a/Essay.pages\0.sh"))
    }

    func testOnlyOrdinaryWebPagesMayBeOpened() {
        XCTAssertEqual(ReopenPolicy.pageURL("https://notes.example.com/week3?x=1")?.host, "notes.example.com")
        XCTAssertEqual(ReopenPolicy.pageURL("notes.example.com/week3")?.scheme, "https", "an address without a scheme is a web page")
        for bad in ["file:///etc/passwd", "javascript:alert(1)", "x-apple.systempreferences:com.apple.Siri", "ftp://h/x", "https://user:pw@example.com/", "", "https://"] {
            XCTAssertNil(ReopenPolicy.pageURL(bad), bad)
        }
    }

    func testAppNamesCannotEscapeTheApplicationsFolders() {
        XCTAssertTrue(ReopenPolicy.appPaths(named: "Pages", home: "/Users/a").contains("/Applications/Pages.app"))
        XCTAssertTrue(ReopenPolicy.appPaths(named: "Pages", home: "/Users/a").contains("/Users/a/Applications/Pages.app"))
        XCTAssertTrue(ReopenPolicy.appPaths(named: "../../tmp/evil").isEmpty); XCTAssertTrue(ReopenPolicy.appPaths(named: "").isEmpty)
    }
}

final class BackShortcutTests: XCTestCase {
    func testTheKeysAreDistinctAndOffMeansNoKey() {
        XCTAssertEqual(Set(BackShortcut.allCases.filter(\.isOn).map { "\($0.keyCode)-\($0.carbonModifiers)" }).count, 3)
        XCTAssertFalse(BackShortcut.off.isOn)
        XCTAssertNotEqual(BackShortcut.controlOptionB.carbonModifiers, BackShortcut.commandControlB.carbonModifiers)
    }

    func testNoShortcutClashesWithParkingAThought() {
        for b in BackShortcut.allCases where b.isOn {
            for p in ParkingShortcut.allCases { XCTAssertFalse(b.keyCode == p.keyCode && b.carbonModifiers == p.carbonModifiers, "\(b.label) vs \(p.label)") }
        }
    }
}

@MainActor
final class MoreWaysBackTests: XCTestCase {
    var t = 0.0
    var went: [WindowSnapshot] = []
    var reopens: [Bool] = []
    let judge = ScriptedJudge(markers: [("Notes", .on), ("Pages", .on), ("Keynote", .on), ("youtube", .off), ("Slack", .off)])
    let pages = WindowSnapshot(app: "Pages", title: "Pages essay", documentPath: "/Users/a/Essay.pages")
    let notes = WindowSnapshot(app: "Notes", title: "Notes lecture")
    let term = WindowSnapshot(app: "Keynote", title: "Keynote deck for Notes")
    let slack = WindowSnapshot(app: "Slack", title: "General")

    func make(configure: (SessionController) -> Void = { _ in }) -> SessionController {
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { [unowned self] in self.t })
        c.onGoToPlace = { [unowned self] w, _, reopen in went.append(w); reopens.append(reopen); return .exact }
        configure(c)
        return c
    }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }
    func drift(_ c: SessionController) async {
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 60)
        c.windowChanged(notes); await advance(c, to: 120)
        c.windowChanged(term); await advance(c, to: 180)
        c.windowChanged(slack); await advance(c, to: 185)
    }

    // MARK: the whole task comes back

    func testTheWindowsYouWorkedInComeForwardWithTheMainOneOnTop() async {
        let c = make()
        await drift(c)
        c.act(.backToTask)
        XCTAssertEqual(went.map(\.app), ["Pages", "Notes", "Keynote"], "the two other windows first, oldest first, then the place itself on top")
        XCTAssertEqual(reopens, [false, false, true], "only the main place is opened again if it is gone; the others are not chased")
    }

    func testTheWorkingSetIsOptionalAndNeverUsedInPractice() async {
        let off = make { $0.prefs.bringWorkingSet = false }
        await drift(off); off.act(.backToTask)
        XCTAssertEqual(went.map(\.app), ["Keynote"])
        went = []; reopens = []; t = 0
        let practice = make()
        practice.windowChanged(pages); practice.begin(task: "Calc homework", preset: .standard, shadow: true)
        await advance(practice, to: 60); practice.windowChanged(notes); await advance(practice, to: 120); practice.windowChanged(slack); await advance(practice, to: 125)
        practice.act(.backToTask)
        XCTAssertEqual(went.map(\.app), ["Notes"], "practice sessions leave your other windows alone")
    }

    // MARK: a closed place is opened again

    func testOpeningAgainIsAllowedOnYourTripAndSwitchableAndNeverInPractice() async {
        let c = make()
        await drift(c); c.act(.backToTask)
        XCTAssertEqual(reopens.last, true)

        went = []; reopens = []; t = 0
        let off = make { $0.prefs.reopenClosed = false }
        await drift(off); off.act(.backToTask)
        XCTAssertEqual(reopens.last, false)

        went = []; reopens = []; t = 0
        let practice = make()
        practice.windowChanged(pages); practice.begin(task: "Calc homework", preset: .standard, shadow: true)
        await advance(practice, to: 60); practice.windowChanged(slack); await advance(practice, to: 65)
        practice.act(.backToTask)
        XCTAssertEqual(reopens.last, false)
    }

    func testTheLaddersOwnReturnNeverOpensAnythingAgain() async {
        let c = make()
        await drift(c)
        c.ladderReturning = true
        c.act(.backToTask)
        XCTAssertEqual(reopens.last, false, "only a trip you asked for may open a document")
    }

    func testAPlaceThatWasOpenedAgainSaysSo() async {
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { [unowned self] in self.t })
        c.onGoToPlace = { _, _, _ in .reopened }
        await drift(c); c.act(.backToTask)
        XCTAssertEqual(c.lastReturn?.outcome, .reopened)
    }

    // MARK: back to your spot

    func testYourSpotIsNotedWhileYouWorkAndNotWhileYouDrift() async {
        let c = make()
        var reads: [String] = []
        c.onReadPosition = { w in reads.append(w.app); return PlacePosition(scroll: 0.4, caret: 12, characters: 100) }
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 30)
        XCTAssertGreaterThanOrEqual(reads.count, 5)
        XCTAssertEqual(c.places.all.first?.position?.scroll, 0.4)
        c.windowChanged(slack); await advance(c, to: 40)
        let n = reads.count
        await advance(c, to: 80)
        XCTAssertEqual(reads.count, n, "nothing is read while you are somewhere that is not the task")
        XCTAssertFalse(reads.contains("Slack"))
    }

    func testBackToTaskPutsYouBackAtYourSpot() async {
        let c = make()
        var restored: [(String, Double?)] = []
        c.onReadPosition = { _ in PlacePosition(scroll: 0.4, caret: 12, characters: 100) }
        c.onRestorePosition = { w, p in restored.append((w.app, p.scroll)); return true }
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 60)
        c.windowChanged(slack); await advance(c, to: 70)
        c.act(.backToTask)
        await advance(c, to: 72)
        XCTAssertTrue(restored.isEmpty, "not until the place is actually in front")
        c.windowChanged(pages); await advance(c, to: 73)
        XCTAssertEqual(restored.count, 1); XCTAssertEqual(restored.first?.0, "Pages"); XCTAssertEqual(restored.first?.1, 0.4)
        XCTAssertEqual(c.lastSpotRestored, true)
        await advance(c, to: 90)
        XCTAssertEqual(restored.count, 1, "once")
    }

    func testAnAppThatWillNotMoveGetsAFewTriesThenIsLeftAlone() async {
        let c = make()
        var tries = 0
        c.onReadPosition = { _ in PlacePosition(scroll: 0.4) }
        c.onRestorePosition = { _, _ in tries += 1; return false }
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 60); c.windowChanged(slack); await advance(c, to: 70)
        c.act(.backToTask); c.windowChanged(pages)
        await advance(c, to: 90)
        XCTAssertEqual(tries, 4)
        XCTAssertEqual(c.lastSpotRestored, false)
    }

    func testYourSpotIsLeftAloneWhenSwitchedOffInPracticeOrNeverNoted() async {
        let off = make { $0.prefs.restoreSpot = false }
        var reads = 0
        off.onReadPosition = { _ in reads += 1; return PlacePosition(scroll: 0.4) }
        off.onRestorePosition = { _, _ in XCTFail("switched off"); return true }
        off.windowChanged(pages); off.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(off, to: 40); off.windowChanged(slack); await advance(off, to: 45)
        off.act(.backToTask); off.windowChanged(pages); await advance(off, to: 50)
        XCTAssertEqual(reads, 0)

        t = 0
        let blank = make()
        blank.onReadPosition = { _ in nil }
        blank.onRestorePosition = { _, _ in XCTFail("no spot was ever noted"); return true }
        blank.windowChanged(pages); blank.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(blank, to: 40); blank.windowChanged(slack); await advance(blank, to: 45)
        blank.act(.backToTask); blank.windowChanged(pages); await advance(blank, to: 50)
    }

    // MARK: the key

    func testTheKeyDoesBackToTaskDuringASessionAndNothingOtherwise() async {
        let c = make()
        c.backToTaskFromShortcut()
        XCTAssertTrue(went.isEmpty, "no session, nothing to go back to")
        await drift(c)
        c.backToTaskFromShortcut()
        XCTAssertEqual(went.last?.app, "Keynote")
    }

    func testTheNewSwitchesStartOnAndTheKeyIsControlOptionB() {
        let p = noWords()
        XCTAssertTrue(p.reopenClosed); XCTAssertTrue(p.restoreSpot); XCTAssertTrue(p.bringWorkingSet)
        XCTAssertEqual(p.backShortcut, .controlOptionB)
    }
}

final class FocusLinkTests: XCTestCase {
    func testOnlyBackToTaskIsUnderstood() {
        for ok in ["focusapp://back", "focusapp:///back", "focusapp:back", "FOCUSAPP://Back", "focusapp://back/", "focusapp://back?from=shortcuts"] {
            XCTAssertEqual(FocusLink.action(from: URL(string: ok)!), .backToTask, ok)
        }
        for no in ["focusapp://pause", "focusapp://end", "focusapp://", "focusapp://back/../end", "https://back", "other://back", "focusapp://backup"] {
            XCTAssertNil(FocusLink.action(from: URL(string: no)!), no)
        }
    }
}

@MainActor
final class LinksAndPuttingAwayTests: XCTestCase {
    var t = 0.0
    var wall = Date(timeIntervalSince1970: 1_000_000)
    var went: [String] = [], hidden: [String] = [], order: [String] = []
    let judge = ScriptedJudge(markers: [("Notes", .on), ("Pages", .on), ("youtube", .off), ("Slack", .off), ("Messages", .off)])
    let pages = WindowSnapshot(app: "Pages", title: "Pages essay", documentPath: "/Users/a/Essay.pages")
    let slack = WindowSnapshot(app: "Slack", title: "General")
    let finder = WindowSnapshot(app: "Finder", title: "Downloads")

    func make(configure: (SessionController) -> Void = { _ in }) -> SessionController {
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { [unowned self] in self.t }, date: { [unowned self] in self.wall })
        c.onGoToPlace = { [unowned self] w, _, _ in went.append(w.app); order.append("go " + w.app); return .exact }
        c.onHideApp = { [unowned self] in hidden.append($0); order.append("hide " + $0) }
        c.prefs.bringWorkingSet = false
        configure(c)
        return c
    }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }
    func driftInto(_ c: SessionController, _ w: WindowSnapshot, task: String = "Calc homework", shadow: Bool = false) async {
        c.windowChanged(pages); c.begin(task: task, preset: .standard, shadow: shadow)
        await advance(c, to: 60)
        c.windowChanged(w); await advance(c, to: 110)
    }

    // MARK: a link

    func testALinkDoesBackToTaskOnlyDuringASessionAndOnlyWhenAllowed() async {
        let c = make()
        XCTAssertFalse(c.handleLink(URL(string: "focusapp://back")!), "no session")
        await driftInto(c, slack)
        XCTAssertFalse(c.handleLink(URL(string: "focusapp://pause")!), "only Back to task")
        XCTAssertFalse(c.handleLink(URL(string: "https://example.com/")!))
        XCTAssertTrue(c.handleLink(URL(string: "focusapp://back")!))
        XCTAssertEqual(went, ["Pages"])

        went = []; t = 0
        let off = make { $0.prefs.allowBackLink = false }
        await driftInto(off, slack)
        XCTAssertFalse(off.handleLink(URL(string: "focusapp://back")!))
        XCTAssertTrue(went.isEmpty)
    }

    func testABurstOfLinksCountsOnce() async {
        let c = make()
        await driftInto(c, slack)
        XCTAssertTrue(c.handleLink(URL(string: "focusapp://back")!))
        XCTAssertTrue(c.handleLink(URL(string: "focusapp://back")!))
        XCTAssertTrue(c.handleLink(URL(string: "focusapp://back")!))
        XCTAssertEqual(went.count, 1, "a page that opens the link in a loop cannot keep pulling windows around")
        wall = wall.addingTimeInterval(3)
        XCTAssertTrue(c.handleLink(URL(string: "focusapp://back")!))
        XCTAssertEqual(went.count, 2)
    }

    func testTheDockMenuNamesWhereItGoes() async {
        let c = make()
        XCTAssertEqual(c.backToTaskTitle, "Back to task")
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 10)
        XCTAssertEqual(c.backToTaskTitle, "Back to Pages \u{00B7} Pages essay")
    }

    // MARK: putting the drifted app away

    func testTheAppYouDriftedIntoIsHiddenAfterTheTripWhenYouAskForThat() async {
        let c = make { $0.prefs.putAwayOnReturn = true }
        await driftInto(c, slack)
        XCTAssertTrue(["drifting", "interrupted"].contains(c.presence.state), c.presence.state)
        c.act(.backToTask)
        XCTAssertEqual(hidden, ["Slack"])
        XCTAssertEqual(order, ["go Pages", "hide Slack"], "the task comes forward first, then the other app goes away")
    }

    func testNothingIsHiddenByDefault() async {
        let c = make()
        await driftInto(c, slack); c.act(.backToTask)
        XCTAssertTrue(hidden.isEmpty)
    }

    func testFinderAndSystemAppsAreNeverHiddenAndNeitherIsTheTaskApp() async {
        let c = make { $0.prefs.putAwayOnReturn = true }
        await driftInto(c, finder); c.act(.backToTask)
        XCTAssertTrue(hidden.isEmpty, "Finder is protected")

        went = []; hidden = []; order = []; t = 0
        let same = make { $0.prefs.putAwayOnReturn = true }
        same.windowChanged(pages); same.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(same, to: 60)
        same.windowChanged(WindowSnapshot(app: "Pages", title: "Pages scratch", documentPath: "/Users/a/Scratch.pages")); await advance(same, to: 110)
        same.act(.backToTask)
        XCTAssertTrue(hidden.isEmpty, "another window of the same app is not put away")
    }

    func testAppsOnTheNeverJudgedListAndPracticeAreLeftAlone() async {
        let c = make { $0.prefs.putAwayOnReturn = true }
        await driftInto(c, WindowSnapshot(app: "Messages", title: "Mum"))
        c.act(.backToTask)
        XCTAssertTrue(hidden.isEmpty, "personal messages are on the never-judged list")

        went = []; hidden = []; order = []; t = 0
        let practice = make { $0.prefs.putAwayOnReturn = true }
        await driftInto(practice, slack, shadow: true); practice.act(.backToTask)
        XCTAssertTrue(hidden.isEmpty, "practice sessions never touch other apps")
    }

    func testTheLaddersOwnReturnDoesNotHideTwice() async {
        let c = make { $0.prefs.putAwayOnReturn = true }
        await driftInto(c, slack)
        c.ladderReturning = true
        c.act(.backToTask)
        XCTAssertTrue(hidden.isEmpty, "the ladder has its own hide step")
    }

    func testPuttingAwayIsNotDoneWhenYouWereAlreadyBackOnTask() async {
        let c = make { $0.prefs.putAwayOnReturn = true }
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 30)
        c.act(.backToTask)
        XCTAssertTrue(hidden.isEmpty)
    }
}

@MainActor
final class BeaconTests: XCTestCase {
    var t = 0.0
    let judge = ScriptedJudge(markers: [("Pages", .on), ("Slack", .off)])
    let pages = WindowSnapshot(app: "Pages", title: "Pages essay", documentPath: "/Users/a/Essay.pages")
    let slack = WindowSnapshot(app: "Slack", title: "General")

    func make(on: Bool = true, shadow: Bool = false) -> SessionController {
        let prefs = noWords(); prefs.beaconRing = on
        let c = SessionController(judge: judge, store: DataStore(), prefs: prefs, now: { [unowned self] in self.t })
        c.onGoToPlace = { _, _, _ in .exact }
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: shadow)
        return c
    }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }

    func testItIsOffUntilYouTurnItOn() {
        XCTAssertFalse(noWords().beaconRing)
    }

    func testTheWindowBackToTaskWouldGoToIsMarkedOnlyDuringARealNudge() async {
        let c = make()
        await advance(c, to: 60)
        XCTAssertNil(c.beaconPlace, "on task: nothing to mark")
        c.windowChanged(slack); await advance(c, to: 70)
        XCTAssertNotEqual(c.presence.state, "interrupted")
        XCTAssertNil(c.beaconPlace, "the first doubt is not a nudge")
        await advance(c, to: 200)
        XCTAssertEqual(c.presence.state, "interrupted")
        XCTAssertEqual(c.beaconPlace?.window.app, "Pages")
    }

    func testNothingIsMarkedWhenSwitchedOffInPracticeOrAlreadyThere() async {
        let off = make(on: false)
        await advance(off, to: 60); off.windowChanged(slack); await advance(off, to: 200)
        XCTAssertNil(off.beaconPlace)

        t = 0
        let practice = make(shadow: true)
        await advance(practice, to: 60); practice.windowChanged(slack); await advance(practice, to: 200)
        XCTAssertNil(practice.beaconPlace)

        t = 0
        let c = make()
        await advance(c, to: 60); c.windowChanged(slack); await advance(c, to: 200)
        c.windowChanged(pages)
        XCTAssertNil(c.beaconPlace, "you are in that window already")
    }

    func testTheRingFollowsTheWindowAndGoesWhenYouAreBack() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let c = make()
        var frame = CGRect(x: 100, y: 120, width: 800, height: 600)
        c.frameForPlace = { _ in frame }
        let b = BeaconController(controller: c)
        await advance(c, to: 60); c.windowChanged(slack); await advance(c, to: 200)
        b.update()
        XCTAssertTrue(b.isShowing)
        let primaryH = NSScreen.screens[0].frame.height
        XCTAssertEqual(try XCTUnwrap(b.frameForTesting).minY, primaryH - 120 - 600 - 3, accuracy: 0.5)
        frame = CGRect(x: 300, y: 120, width: 800, height: 600)
        b.update()
        XCTAssertEqual(try XCTUnwrap(b.frameForTesting).minX, 297, accuracy: 0.5, "it follows the window if it moves")
        c.windowChanged(pages); b.update()
        XCTAssertFalse(b.isShowing, "gone the moment you are back")
        b.stop()
    }

    func testNoRingWhenTheWindowCannotBeFoundOrIsTiny() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let c = make()
        let b = BeaconController(controller: c)
        await advance(c, to: 60); c.windowChanged(slack); await advance(c, to: 200)
        c.frameForPlace = { _ in nil }; b.update()
        XCTAssertFalse(b.isShowing)
        c.frameForPlace = { _ in CGRect(x: 0, y: 0, width: 60, height: 40) }; b.update()
        XCTAssertFalse(b.isShowing, "a sliver is not worth outlining")
        b.stop()
    }
}

@MainActor
final class GrayOnlyTheDriftedWindowTests: XCTestCase {
    var t = 0.0
    let judge = ScriptedJudge(markers: [("Pages", .on), ("Slack", .off)])
    let pages = WindowSnapshot(app: "Pages", title: "Pages essay", documentPath: "/Users/a/Essay.pages")
    let slack = WindowSnapshot(app: "Slack", title: "General")
    let frame = CGRect(x: 200, y: 100, width: 900, height: 700)

    func make(only: Bool = true) -> SessionController {
        let prefs = noWords(); prefs.grayWindowOnly = only
        let c = SessionController(judge: judge, store: DataStore(), prefs: prefs, now: { [unowned self] in self.t })
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        return c
    }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }

    func testItIsOffByDefaultAndTheWholeScreenIsGrayedWhenOff() async {
        XCTAssertFalse(noWords().grayWindowOnly)
        let c = make(only: false)
        XCTAssertEqual(c.veilRegion(windowFrame: frame), .screens)
    }

    func testOnlyTheWindowYouDriftedIntoIsGrayed() async {
        let c = make()
        await advance(c, to: 60); c.windowChanged(slack); await advance(c, to: 300)
        XCTAssertGreaterThan(c.veilLevel(), 30)
        XCTAssertEqual(c.veilRegion(windowFrame: frame), .window(frame))
    }

    func testNothingIsGrayedWhenTheDriftedWindowCannotBeTold() async {
        let c = make()
        await advance(c, to: 60); c.windowChanged(slack); await advance(c, to: 300)
        XCTAssertEqual(c.veilRegion(windowFrame: nil), .none, "Focus itself in front, or an unknown frame")
        XCTAssertEqual(c.veilRegion(windowFrame: CGRect(x: 0, y: 0, width: 50, height: 30)), .none, "a sliver")
    }

    func testTheTaskWindowIsNeverGrayedAndThePreviewCoversTheScreen() async {
        let c = make()
        await advance(c, to: 60); c.windowChanged(slack); await advance(c, to: 300)
        c.windowChanged(pages)
        XCTAssertEqual(c.veilRegion(windowFrame: frame), .none, "back in the task window the gray must not sit on it")
        c.previewVeil()
        XCTAssertEqual(c.veilRegion(windowFrame: nil), .screens, "there is no drifted window to show a preview on")
    }

    func testThePanelSitsOnThatWindowAndGoesWhenYouAreBack() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let c = make()
        c.frontWindowFrame = { [unowned self] in frame }
        let v = VeilController(controller: c)
        await advance(c, to: 60); c.windowChanged(slack); await advance(c, to: 300)
        v.update()
        let f = try XCTUnwrap(v.windowPanelFrameForTesting)
        let primaryH = NSScreen.screens[0].frame.height
        XCTAssertEqual(f.minX, 200, accuracy: 0.5); XCTAssertEqual(f.width, 900, accuracy: 0.5)
        XCTAssertEqual(f.minY, primaryH - 100 - 700, accuracy: 0.5, "Core Graphics counts from the top, Cocoa from the bottom")
        c.windowChanged(pages); v.update()
        XCTAssertNil(v.windowPanelFrameForTesting)
        v.stop()
    }
}

final class CueTraceTests: XCTestCase {
    func testTheLastCueToAppearIsTheOneCredited() {
        var tr = CueTrace()
        tr.observe([], at: 10)
        tr.observe([.banner], at: 20); tr.observe([.banner], at: 21)
        tr.observe([.banner, .gray], at: 50)
        let r = tr.finish(returnedAt: 80, sinceDrift: 70)
        XCTAssertEqual(r.cue, .gray); XCTAssertEqual(r.seconds, 30)
    }

    func testComingBackBeforeAnyCueIsItsOwnAnswer() {
        var tr = CueTrace()
        let r = tr.finish(returnedAt: 12, sinceDrift: 12)
        XCTAssertNil(r.cue); XCTAssertEqual(r.seconds, 12)
    }

    func testACueThatAppearedAfterYouWereBackIsNotCredited() {
        var tr = CueTrace()
        tr.observe([.banner], at: 20)
        tr.observe([.banner, .card], at: 70)   // appeared while the brain was still confirming the return
        let r = tr.finish(returnedAt: 60, sinceDrift: 60)
        XCTAssertEqual(r.cue, .banner); XCTAssertEqual(r.seconds, 40)
    }

    func testACueThatCameBackCountsFromItsLatestAppearanceAndFinishingClearsTheTrace() {
        var tr = CueTrace()
        tr.observe([.banner], at: 10); tr.observe([], at: 20); tr.observe([.banner], at: 40)
        XCTAssertEqual(tr.finish(returnedAt: 60, sinceDrift: 50).seconds, 20)
        XCTAssertNil(tr.finish(returnedAt: 90, sinceDrift: 5).cue, "a new stretch starts clean")
    }

    func testAtLeastOneSecond() {
        var tr = CueTrace(); tr.observe([.card], at: 30)
        XCTAssertEqual(tr.finish(returnedAt: 30, sinceDrift: 30).seconds, 1)
    }
}

final class CueResponseTests: XCTestCase {
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    func session(_ returns: [ReturnCue], daysAgo: Int = 1, practice: Bool? = nil) -> SessionRecord {
        let s = day.addingTimeInterval(Double(-daysAgo) * 86_400)
        return SessionRecord(projectId: nil, task: "x", timed: false, start: s, end: s.addingTimeInterval(1800), activeSeconds: 1800, offTopicSeconds: 0, unsureSeconds: 0,
                             drifts: returns.count, interrupts: 0, refusals: 0, shadowMarks: 0, segments: [], practice: practice, returnCues: returns)
    }
    func many(_ cue: CueKind?, _ secs: [Double]) -> [ReturnCue] { secs.map { ReturnCue(cue: cue, seconds: $0) } }

    func testTheTypicalTimePerCueFastestFirstAndOnlyWithEnoughReturns() {
        let r = Rewards.cueResponses([session(many(.gray, [10, 20, 30, 40]) + many(.banner, [60, 70, 80]) + many(.card, [5, 6]))], today: day)
        XCTAssertEqual(r.map(\.cue), [.gray, .banner], "two returns after the card are too few to say anything")
        XCTAssertEqual(r[0].median, 25, "the middle of an even count is the mean of the two in the middle")
        XCTAssertEqual(r[1].median, 70); XCTAssertEqual(r[1].count, 3)
    }

    func testReturnsBeforeAnyCueAreTheirOwnRow() {
        let r = Rewards.cueResponses([session(many(nil, [8, 9, 12]))], today: day)
        XCTAssertEqual(r.count, 1); XCTAssertNil(r[0].cue)
    }

    func testPracticeAndOldSessionsAreLeftOut() {
        XCTAssertTrue(Rewards.cueResponses([session(many(.gray, [10, 20, 30]), practice: true)], today: day).isEmpty)
        XCTAssertTrue(Rewards.cueResponses([session(many(.gray, [10, 20, 30]), daysAgo: 45)], today: day).isEmpty)
    }

    func testOldSavedSessionsWithoutTheFieldStillLoadAndNewOnesRoundTrip() throws {
        let old = session([])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "returnCues")
        let back = try JSONDecoder().decode(SessionRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(back.returnCues)
        let fresh = session(many(.edges, [14]))
        XCTAssertEqual(try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(fresh)).returnCues, many(.edges, [14]))
    }

    func testOnlyKindsAndSecondsAreSaved() throws {
        let data = try JSONEncoder().encode(session(many(.gray, [12])))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"gray\"")); XCTAssertFalse(text.contains("Slack"))
    }
}

@MainActor
final class CueTraceInSessionTests: XCTestCase {
    var t = 0.0
    let judge = ScriptedJudge(markers: [("Pages", .on), ("Slack", .off)])
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }

    func testAReturnIsSavedWithTheCueThatWasShowing() async {
        let store = DataStore()
        let prefs = noWords()
        let c = SessionController(judge: judge, store: store, prefs: prefs, now: { [unowned self] in self.t })
        let pages = WindowSnapshot(app: "Pages", title: "Pages essay", documentPath: "/Users/a/Essay.pages")
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: false)
        await advance(c, to: 60)
        c.windowChanged(WindowSnapshot(app: "Slack", title: "General")); await advance(c, to: 220)
        c.windowChanged(pages); await advance(c, to: 260)
        c.end(); await advance(c, to: 262)
        let saved = try? XCTUnwrap(store.sessions.first)
        XCTAssertEqual(saved?.returnCues?.count, 1, "one drift, one return")
        XCTAssertNotNil(saved?.returnCues?.first?.cue, "by then a cue had appeared")
        XCTAssertEqual(saved?.returns?.count, 1)
    }

    func testPracticeSessionsRecordNothing() async {
        let store = DataStore()
        let c = SessionController(judge: judge, store: store, prefs: noWords(), now: { [unowned self] in self.t })
        let pages = WindowSnapshot(app: "Pages", title: "Pages essay", documentPath: "/Users/a/Essay.pages")
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: true)
        await advance(c, to: 60); c.windowChanged(WindowSnapshot(app: "Slack", title: "General")); await advance(c, to: 220)
        c.windowChanged(pages); await advance(c, to: 260); c.end(); await advance(c, to: 262)
        XCTAssertNil(store.sessions.first?.returnCues)
    }
}

final class HaloMathTests: XCTestCase {
    func testTheRingGrowsAndStrengthensWithTheDriftAndIsHiddenAtTheStart() {
        XCTAssertLessThan(Halo.radius(10), Halo.radius(50)); XCTAssertLessThan(Halo.radius(50), Halo.radius(100))
        XCTAssertEqual(Halo.radius(100), 110); XCTAssertEqual(Halo.radius(-5), 20); XCTAssertEqual(Halo.radius(400), 110)
        XCTAssertEqual(Halo.opacity(0), 0); XCTAssertEqual(Halo.opacity(2), 0)
        XCTAssertLessThan(Halo.opacity(10), Halo.opacity(90)); XCTAssertLessThanOrEqual(Halo.opacity(500), 0.65)
    }
}

@MainActor
final class CursorHaloTests: XCTestCase {
    var t = 0.0
    let judge = ScriptedJudge(markers: [("Pages", .on), ("Slack", .off)])
    let pages = WindowSnapshot(app: "Pages", title: "Pages essay", documentPath: "/Users/a/Essay.pages")
    func make(on: Bool = true, shadow: Bool = false) -> SessionController {
        let prefs = noWords(); prefs.cursorHalo = on
        let c = SessionController(judge: judge, store: DataStore(), prefs: prefs, now: { [unowned self] in self.t })
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: shadow)
        return c
    }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }

    func testItIsOffByDefaultAndNeverShowsOnTaskOrInPractice() async {
        XCTAssertFalse(noWords().cursorHalo)
        let c = make()
        await advance(c, to: 60)
        XCTAssertEqual(c.haloLevel(), 0, "on task: nothing")
        let off = make(on: false); t = 0
        off.windowChanged(WindowSnapshot(app: "Slack", title: "General")); await advance(off, to: 200)
        XCTAssertEqual(off.haloLevel(), 0, "switched off")
        t = 0
        let practice = make(shadow: true)
        practice.windowChanged(WindowSnapshot(app: "Slack", title: "General")); await advance(practice, to: 200)
        XCTAssertEqual(practice.haloLevel(), 0)
    }

    func testItGrowsAsYouStayAwayAndTheSettingsPreviewRuns() async {
        let c = make()
        await advance(c, to: 60); c.windowChanged(WindowSnapshot(app: "Slack", title: "General"))
        await advance(c, to: 90); let early = c.haloLevel()
        await advance(c, to: 300); let late = c.haloLevel()
        XCTAssertGreaterThan(late, early); XCTAssertGreaterThan(late, 50)
        let calm = make(); t = 0
        calm.previewHalo()
        t = 6
        XCTAssertEqual(calm.haloLevel(), 100, "the preview holds at the top")
        XCTAssertTrue(calm.isPreviewingHalo)
    }

    func testTheRingFollowsThePointerAndTheTimerSlowsDownWhenItIsGone() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let c = make()
        let h = HaloController(controller: c)
        var at = NSPoint(x: 500, y: 400)
        h.pointer = { at }
        h.start()
        h.update()
        XCTAssertFalse(h.isShowing); XCTAssertFalse(h.isFast, "nothing to show: it only waits")
        c.previewHalo(); t = 6
        h.update()
        XCTAssertTrue(h.isShowing); XCTAssertTrue(h.isFast)
        var f = try XCTUnwrap(h.frameForTesting)
        XCTAssertEqual(f.midX, 500, accuracy: 1); XCTAssertEqual(f.midY, 400, accuracy: 1)
        at = NSPoint(x: 800, y: 300); h.update()
        f = try XCTUnwrap(h.frameForTesting)
        XCTAssertEqual(f.midX, 800, accuracy: 1); XCTAssertEqual(f.midY, 300, accuracy: 1)
        t = 100; for _ in 0..<7 { h.update() }   // the level is re-read every sixth look
        XCTAssertFalse(h.isShowing); XCTAssertFalse(h.isFast, "gone and back to waiting")
        h.stop()
    }
}

final class SoundEaseRulesTests: XCTestCase {
    func win(_ app: String, _ title: String, url: String = "") -> WindowSnapshot { WindowSnapshot(app: app, title: title, url: url) }

    func testVideoSitesByAddressAndByNameInABrowserTitle() {
        XCTAssertTrue(SoundEase.looksLikeVideo(win("Safari", "clip", url: "https://www.youtube.com/watch?v=1")))
        XCTAssertTrue(SoundEase.looksLikeVideo(win("Google Chrome", "x", url: "https://youtu.be/abc")))
        XCTAssertTrue(SoundEase.looksLikeVideo(win("Safari", "Stranger Things - Netflix")))
        XCTAssertFalse(SoundEase.looksLikeVideo(win("Safari", "x", url: "https://notyoutube.com/")), "a lookalike host is not YouTube")
        XCTAssertFalse(SoundEase.looksLikeVideo(win("Safari", "Notes", url: "https://notes.example.com/")))
        XCTAssertFalse(SoundEase.looksLikeVideo(win("Pages", "Essay about YouTube")), "a document that mentions it is not a video page")
    }

    func testTheVolumeStepsTowardTheGoalAndSettles() {
        var v: Float = 0.8
        for _ in 0..<30 { v = SoundEase.step(from: v, to: 0.28, rate: SoundEase.downRate) }
        XCTAssertEqual(v, 0.28, accuracy: 0.0001)
        XCTAssertEqual(SoundEase.step(from: 0.5, to: 0.505, rate: 0.3), 0.505, "close enough lands exactly")
    }

    func testWhatIsRememberedRoundTripsAndRefusesNonsense() {
        let s = SoundEase.Saved(original: 0.6, lowered: 0.21)
        XCTAssertEqual(SoundEase.Saved(text: s.text), s)
        for bad in ["", "0.5", "a,b", "1.5,0.2", "0.5,0.2,0.1", "-1,0"] { XCTAssertNil(SoundEase.Saved(text: bad), bad) }
    }

    func testAfterACrashTheVolumeIsGivenBackOnlyIfItIsStillWhereFocusLeftIt() {
        let s = SoundEase.Saved(original: 0.6, lowered: 0.21)
        XCTAssertEqual(SoundEase.recover(saved: s, current: 0.21), 0.6)
        XCTAssertNil(SoundEase.recover(saved: s, current: 0.4), "somewhere else: it is yours")
        XCTAssertEqual(SoundEase.recover(saved: SoundEase.Saved(original: 0.6, lowered: 0.4), current: 0.4), 0.6, "a crash on the way down, saved where it had got to")
        XCTAssertNil(SoundEase.recover(saved: s, current: 0.05), "you turned it down yourself")
        XCTAssertNil(SoundEase.recover(saved: s, current: 0.9), "you turned it up yourself")
        XCTAssertNil(SoundEase.recover(saved: nil, current: 0.2)); XCTAssertNil(SoundEase.recover(saved: s, current: nil))
    }
}

final class FakeVolume: SystemVolume {
    var level: Float?
    var writes: [Float] = []
    var canWrite = true
    init(_ v: Float?) { level = v }
    func read() -> Float? { level }
    func write(_ value: Float) -> Bool { guard canWrite else { return false }; level = value; writes.append(value); return true }
}

@MainActor
final class SoundEaseInSessionTests: XCTestCase {
    var t = 0.0
    let judge = ScriptedJudge(markers: [("Pages", .on), ("youtube", .off), ("Slack", .off)])
    let pages = WindowSnapshot(app: "Pages", title: "Pages essay", documentPath: "/Users/a/Essay.pages")
    let video = WindowSnapshot(app: "Safari", title: "cat video - YouTube", url: "https://www.youtube.com/watch?v=1")
    var saved: [SoundEase.Saved?] = []

    func make(on: Bool = true, shadow: Bool = false, volume: FakeVolume) -> SessionController {
        let prefs = noWords(); prefs.easeSound = on
        let c = SessionController(judge: judge, store: DataStore(), prefs: prefs, now: { [unowned self] in self.t })
        c.systemVolume = volume
        c.onSoundSaved = { [unowned self] in saved.append($0) }
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: shadow)
        return c
    }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }

    func testItIsOffByDefaultAndLeavesTheVolumeAloneUntilThereIsARealNudge() async {
        XCTAssertFalse(noWords().easeSound)
        let v = FakeVolume(0.8)
        let c = make(volume: v)
        await advance(c, to: 60)
        c.windowChanged(video); await advance(c, to: 70)
        XCTAssertNotEqual(c.presence.state, "interrupted")
        XCTAssertTrue(v.writes.isEmpty, "the first doubt is not a nudge")
    }

    func testTheVolumeEasesDownOnAVideoSiteNeverBelowAThirdAndNeverToSilence() async {
        let v = FakeVolume(0.8)
        let c = make(volume: v)
        await advance(c, to: 60); c.windowChanged(video); await advance(c, to: 260)
        XCTAssertEqual(c.presence.state, "interrupted")
        XCTAssertEqual(try XCTUnwrap(v.level), 0.8 * SoundEase.fraction, accuracy: 0.01)
        XCTAssertGreaterThan(v.writes.count, 3, "it eases, it does not jump")
        XCTAssertTrue(v.writes.allSatisfy { $0 >= 0.8 * SoundEase.fraction - 0.001 })
        XCTAssertEqual(saved.last, SoundEase.Saved(original: 0.8, lowered: v.level!), "remembered, where it is now, for a crash")
    }

    func testItComesBackWhenYouDo() async {
        let v = FakeVolume(0.8)
        let c = make(volume: v)
        await advance(c, to: 60); c.windowChanged(video); await advance(c, to: 260)
        c.windowChanged(pages); await advance(c, to: 330)
        XCTAssertEqual(try XCTUnwrap(v.level), 0.8, accuracy: 0.001)
        XCTAssertFalse(saved.isEmpty); XCTAssertNil(saved.last!, "nothing left to put right")
    }

    func testTheSessionEndingGivesTheVolumeBack() async {
        let v = FakeVolume(0.8)
        let c = make(volume: v)
        await advance(c, to: 60); c.windowChanged(video); await advance(c, to: 260)
        XCTAssertLessThan(try XCTUnwrap(v.level), 0.4)
        c.end(); await advance(c, to: 262)
        XCTAssertEqual(try XCTUnwrap(v.level), 0.8, accuracy: 0.001)
    }

    func testQuittingGivesTheVolumeBackToo() async {
        let v = FakeVolume(0.8)
        let c = make(volume: v)
        await advance(c, to: 60); c.windowChanged(video); await advance(c, to: 260)
        c.restoreSound()
        XCTAssertEqual(try XCTUnwrap(v.level), 0.8, accuracy: 0.001)
    }

    func testIfYouChangeTheVolumeYourselfItLetsGoAndNeverFightsYou() async {
        let v = FakeVolume(0.8)
        let c = make(volume: v)
        await advance(c, to: 60); c.windowChanged(video)
        while v.writes.count < 2, t < 300 { await advance(c, to: t + 1) }   // until it has started easing
        XCTAssertGreaterThanOrEqual(v.writes.count, 2)
        v.level = 0.6   // you turned it up
        let n = v.writes.count
        await advance(c, to: 260)
        XCTAssertEqual(v.writes.count, n, "no more writes")
        XCTAssertEqual(try XCTUnwrap(v.level), 0.6, accuracy: 0.0001)
        c.windowChanged(pages); await advance(c, to: 330)
        XCTAssertEqual(try XCTUnwrap(v.level), 0.6, accuracy: 0.0001, "and it does not put 'your old volume' back over yours")
    }

    func testOtherWindowsPracticeSilentOutputsAndFailingOutputsAreLeftAlone() async {
        let slack = FakeVolume(0.8)
        let a = make(volume: slack)
        await advance(a, to: 60); a.windowChanged(WindowSnapshot(app: "Slack", title: "General")); await advance(a, to: 260)
        XCTAssertTrue(slack.writes.isEmpty, "not a video site")

        t = 0; let pv = FakeVolume(0.8)
        let b = make(shadow: true, volume: pv)
        await advance(b, to: 60); b.windowChanged(video); await advance(b, to: 260)
        XCTAssertTrue(pv.writes.isEmpty, "practice")

        t = 0; let quiet = FakeVolume(0.05)
        let q = make(volume: quiet)
        await advance(q, to: 60); q.windowChanged(video); await advance(q, to: 260)
        XCTAssertTrue(quiet.writes.isEmpty, "already nearly silent")

        t = 0; let stuck = FakeVolume(0.8); stuck.canWrite = false
        let s = make(volume: stuck)
        await advance(s, to: 60); s.windowChanged(video); await advance(s, to: 260)
        XCTAssertEqual(stuck.level, 0.8, "an output that cannot be set is left alone")

        t = 0; let off = FakeVolume(0.8)
        let o = make(on: false, volume: off)
        await advance(o, to: 60); o.windowChanged(video); await advance(o, to: 260)
        XCTAssertTrue(off.writes.isEmpty, "switched off")
    }

    func testAfterACrashTheNextLaunchPutsTheVolumeRight() {
        let v = FakeVolume(0.28)
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { 0 })
        c.systemVolume = v
        c.recoverSound(saved: SoundEase.Saved(original: 0.8, lowered: 0.28))
        XCTAssertEqual(try XCTUnwrap(v.level), 0.8, accuracy: 0.0001)
        let mine = FakeVolume(0.5)
        c.systemVolume = mine
        c.recoverSound(saved: SoundEase.Saved(original: 0.8, lowered: 0.28))
        XCTAssertEqual(mine.level, 0.5, "you had changed it since")
    }
}

final class FogMathTests: XCTestCase {
    func testTheBlurGrowsFromNothingAndStaysSoft() {
        XCTAssertEqual(Vignette.fogRadius(0), 0)
        XCTAssertLessThan(Vignette.fogRadius(10), Vignette.fogRadius(60)); XCTAssertLessThan(Vignette.fogRadius(60), Vignette.fogRadius(100))
        XCTAssertEqual(Vignette.fogRadius(100), 14.5, accuracy: 0.01); XCTAssertEqual(Vignette.fogRadius(900), 14.5, accuracy: 0.01)
    }

    @MainActor func testThePanelCarriesABlurWhenTheWindowServerFiltersAreThere() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let p = VeilPanel()
        if p.usesBackdrop { XCTAssertTrue(p.usesBlur, "gray and fog share one backdrop") }
        p.apply(40); p.applyFog(70); p.applyFog(0); p.apply(0)   // must not trap
    }
}

@MainActor
final class FogInSessionTests: XCTestCase {
    var t = 0.0
    let judge = ScriptedJudge(markers: [("Pages", .on), ("Slack", .off)])
    let pages = WindowSnapshot(app: "Pages", title: "Pages essay", documentPath: "/Users/a/Essay.pages")
    let slack = WindowSnapshot(app: "Slack", title: "General")
    func make(on: Bool = true, shadow: Bool = false, windowOnly: Bool = false) -> SessionController {
        let prefs = noWords(); prefs.screenFog = on; prefs.grayWindowOnly = windowOnly
        let c = SessionController(judge: judge, store: DataStore(), prefs: prefs, now: { [unowned self] in self.t })
        c.windowChanged(pages); c.begin(task: "Calc homework", preset: .standard, shadow: shadow)
        return c
    }
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }

    func testItIsOffByDefaultAndSilentOnTaskInPracticeAndWhenSwitchedOff() async {
        XCTAssertFalse(noWords().screenFog)
        let c = make()
        await advance(c, to: 60); XCTAssertEqual(c.fogLevel(), 0)
        t = 0; let off = make(on: false)
        off.windowChanged(slack); await advance(off, to: 250); XCTAssertEqual(off.fogLevel(), 0)
        t = 0; let practice = make(shadow: true)
        practice.windowChanged(slack); await advance(practice, to: 250); XCTAssertEqual(practice.fogLevel(), 0)
    }

    func testItThickensWithTimeAwayAndClearsOnReturn() async {
        let c = make()
        await advance(c, to: 60); c.windowChanged(slack)
        await advance(c, to: 90); let early = c.fogLevel()
        await advance(c, to: 300); let late = c.fogLevel()
        XCTAssertGreaterThan(late, early); XCTAssertGreaterThan(late, 50)
        c.windowChanged(pages); await advance(c, to: 400)
        XCTAssertLessThan(c.fogLevel(), 5)
    }

    func testItGoesWhereTheGrayGoesAndThePreviewCoversTheScreen() async {
        let c = make(windowOnly: true)
        await advance(c, to: 60); c.windowChanged(slack); await advance(c, to: 300)
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertEqual(c.veilRegion(windowFrame: frame), .window(frame))
        c.previewFog()
        XCTAssertEqual(c.veilRegion(windowFrame: nil), .screens, "there is no drifted window to preview on")
    }

    func testTheFogShowsUpAsACueInWhatBringsYouBack() async {
        let c = make()
        await advance(c, to: 60); c.windowChanged(slack); await advance(c, to: 300)
        XCTAssertTrue(CueKind.allCases.contains(.fog))
        XCTAssertEqual(CueKind.fog.label, "Fog")
    }
}

final class SlipTimingTests: XCTestCase {
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    /// A session of 30 minutes active with one slip starting `at` minutes in.
    func session(slipsAtMinutes: [Double], daysAgo: Int = 1, practice: Bool? = nil, active: Double = 1800) -> SessionRecord {
        var segs: [TimelineSegment] = [], t = 0.0
        for m in slipsAtMinutes { segs.append(TimelineSegment(.on, m * 60 - t)); segs.append(TimelineSegment(.off, 60)); t = m * 60 + 60 }
        segs.append(TimelineSegment(.on, max(0, active - t)))
        let s = day.addingTimeInterval(Double(-daysAgo) * 86_400)
        return SessionRecord(projectId: nil, task: "x", timed: false, start: s, end: s.addingTimeInterval(active), activeSeconds: active, offTopicSeconds: 60 * Double(slipsAtMinutes.count),
                             unsureSeconds: 0, drifts: slipsAtMinutes.count, interrupts: 0, refusals: 0, shadowMarks: 0, segments: segs, practice: practice)
    }

    func testSlipsAreCountedByTenMinuteStepsAndAClearPeakIsNamed() {
        let sessions = (0..<6).map { _ in session(slipsAtMinutes: [22]) } + [session(slipsAtMinutes: [4]), session(slipsAtMinutes: [41])]
        let t = Rewards.slipTiming(sessions, today: day)
        XCTAssertEqual(t?.buckets, [1, 0, 6, 0, 1, 0])
        XCTAssertEqual(t?.peak, 2); XCTAssertEqual(Rewards.SlipTiming.label(2), "20 to 30")
    }

    func testAFlatSpreadHasNoPeak() {
        let sessions = [3.0, 12, 24, 33, 44, 53, 8, 26].map { session(slipsAtMinutes: [$0], active: 3600) }
        let t = Rewards.slipTiming(sessions, today: day)
        XCTAssertNotNil(t); XCTAssertNil(t?.peak)
        XCTAssertEqual(t?.buckets.last, 1, "50 minutes and later share the last step")
    }

    func testTooLittleSaysNothing() {
        XCTAssertNil(Rewards.slipTiming([session(slipsAtMinutes: [20]), session(slipsAtMinutes: [20]), session(slipsAtMinutes: [20])], today: day), "three sessions")
        XCTAssertNil(Rewards.slipTiming((0..<6).map { _ in session(slipsAtMinutes: [20]) }.map { var s = $0; s.practice = true; return s }, today: day), "practice says nothing")
        XCTAssertNil(Rewards.slipTiming((0..<9).map { _ in session(slipsAtMinutes: [5], active: 400) }, today: day), "sessions under ten minutes are left out")
        XCTAssertNil(Rewards.slipTiming((0..<9).map { _ in session(slipsAtMinutes: [20], daysAgo: 60) }, today: day), "old sessions")
    }

    func testOneLongDetourIsOneSlip() {
        var s = session(slipsAtMinutes: [20])
        s.segments = [TimelineSegment(.on, 1200), TimelineSegment(.off, 60), TimelineSegment(.off, 60), TimelineSegment(.unsure, 30), TimelineSegment(.off, 60), TimelineSegment(.on, 400)]
        let t = Rewards.slipTiming(Array(repeating: s, count: 4) + (0..<4).map { _ in session(slipsAtMinutes: [20]) }, today: day)
        XCTAssertEqual(t?.total, 8, "two consecutive off segments are one slip; unsure in between does not start another")
    }
}
