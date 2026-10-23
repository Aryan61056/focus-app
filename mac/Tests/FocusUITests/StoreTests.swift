import XCTest
import FocusJudge
@testable import FocusUI

@MainActor
final class StoreTests: XCTestCase {
    func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("focus-test-\(UUID().uuidString).json") }

    func testRoundTripThroughDisk() {
        let u = tmp(); defer { try? FileManager.default.removeItem(at: u) }
        let a = DataStore(url: u)
        let p = a.addProject(name: "Calc homework")
        a.record(SessionRecord(projectId: p.id, task: "Calc homework", timed: false, start: Date(timeIntervalSince1970: 1000), end: Date(timeIntervalSince1970: 2000),
                               activeSeconds: 1000, offTopicSeconds: 60, unsureSeconds: 0, drifts: 1, interrupts: 0, refusals: 0, shadowMarks: 1,
                               segments: [TimelineSegment(.on, 940), TimelineSegment(.off, 60)]))
        let b = DataStore(url: u)
        XCTAssertEqual(b.projects.map { $0.name }, ["Calc homework"])
        XCTAssertEqual(b.sessions.first?.onTaskSeconds, 940)
        XCTAssertEqual(b.sessions(for: p.id).count, 1)
    }

    func testProjectNamedReusesCaseInsensitively() {
        let s = DataStore()
        let a = s.projectNamed("Calc homework"), b = s.projectNamed("calc HOMEWORK")
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(s.projects.count, 1)
    }

    func testLearnedSiteRuleBecomesAProjectRuleAndMatchesNextTime() {
        let s = DataStore(); let p = s.addProject(name: "Calc")
        s.apply(LearnedRule(scope: "project", kind: "allow", keyType: "site", key: "safari|desmos.com"), to: p.id)
        s.apply(LearnedRule(scope: "project", kind: "allow", keyType: "window", key: "safari|khanacademy.org/math/calculus"), to: p.id)
        s.apply(LearnedRule(scope: "project", kind: "deny", keyType: "site", key: "safari|youtube.com"), to: p.id)
        let prof = s.project(p.id)!.profile
        XCTAssertEqual(prof.alwaysAllowDomains, ["desmos.com", "khanacademy.org/math/calculus"])
        XCTAssertEqual(prof.alwaysOffDomains, ["youtube.com"])
        let m = Moment(task: "t", app: "Safari", windowTitle: "x", url: "https://www.desmos.com/calculator", project: prof)
        XCTAssertEqual(Rules.stage1(m)?.label, .onTask)
    }

    func testBareTitleWindowRuleIsNotStoredAsAnAppRule() {
        let s = DataStore(); let p = s.addProject(name: "Calc")
        s.apply(LearnedRule(scope: "project", kind: "allow", keyType: "window", key: "notes|calc homework"), to: p.id)
        XCTAssertTrue(s.project(p.id)!.profile.alwaysAllowApps.isEmpty)
        XCTAssertTrue(s.project(p.id)!.profile.alwaysAllowDomains.isEmpty)
    }

    func testSessionScopedRulesAreNotPersisted() {
        let s = DataStore(); let p = s.addProject(name: "Calc")
        s.apply(LearnedRule(scope: "session", kind: "ignore", keyType: "window", key: "safari|a.com"), to: p.id)
        XCTAssertTrue(s.project(p.id)!.profile.isEmpty)
    }

    func testDeleteEverythingEmptiesTheFile() {
        let u = tmp(); defer { try? FileManager.default.removeItem(at: u) }
        let s = DataStore(url: u); s.addProject(name: "x"); s.deleteEverything()
        XCTAssertTrue(DataStore(url: u).projects.isEmpty)
    }
}

final class StartLineTests: XCTestCase {
    func testNothingTypedSaysNothing() { XCTAssertNil(StartSheet.confirmLine(task: "", project: nil)) }
    func testNewTaskExplainsWhatItIsComparedWith() {
        XCTAssertTrue(StartSheet.confirmLine(task: "Essay", project: nil)!.hasPrefix("New project."))
    }
    func testKnownProjectQuotesItsContextShortened() {
        var p = Project(name: "Calc"); p.context = String(repeating: "integration ", count: 12)
        let line = StartSheet.confirmLine(task: "Calc", project: p)!
        XCTAssertTrue(line.contains("..."))
        XCTAssertLessThan(line.count, 120)
        p.context = ""
        XCTAssertTrue(StartSheet.confirmLine(task: "Calc", project: p)!.hasPrefix("Hushd knows this project."))
    }
}
