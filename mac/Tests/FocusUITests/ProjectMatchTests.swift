import XCTest
@testable import FocusUI

/// Owner, 2026-10-15: projects were being made while typing ("f", "fd", "fdf"...), and a name close to an old project started a second one.
@MainActor
final class ProjectMatchTests: XCTestCase {
    func projects(_ names: [String]) -> [Project] { names.map { Project(name: $0) } }

    func testNormalizeIgnoresCaseSpacingAndPunctuation() {
        XCTAssertEqual(ProjectMatch.normalize("  Do AP  Euro-Vocab! "), "do ap euro vocab")
        XCTAssertEqual(ProjectMatch.normalize("Café"), "cafe")
    }

    func testAnExactNameIsNotSimilarItIsTheSameProject() {
        let ps = projects(["Do AP Euro Vocab", "Calc homework"])
        XCTAssertEqual(ProjectMatch.exact("do ap euro vocab", in: ps)?.name, "Do AP Euro Vocab")
        XCTAssertTrue(ProjectMatch.similar(to: "DO AP EURO VOCAB", in: ps).isEmpty)
    }

    func testPartlyTypedOrExtendedNamesFindTheOldProject() {
        let ps = projects(["Do AP Euro Vocab", "Calc homework"])
        XCTAssertEqual(ProjectMatch.similar(to: "do ap eur", in: ps).first?.name, "Do AP Euro Vocab")
        XCTAssertEqual(ProjectMatch.similar(to: "Calc homework chapter 5", in: ps).first?.name, "Calc homework")
    }

    func testATypoOrAMissingLetterFindsIt() {
        let ps = projects(["Calc homework", "Lab report on pendulums"])
        XCTAssertEqual(ProjectMatch.similar(to: "calc homwork", in: ps).first?.name, "Calc homework")
        XCTAssertEqual(ProjectMatch.similar(to: "lab report on pendulum", in: ps).first?.name, "Lab report on pendulums")
    }

    func testReorderedWordsFindIt() {
        XCTAssertEqual(ProjectMatch.similar(to: "homework calc", in: projects(["Calc homework"])).first?.name, "Calc homework")
    }

    func testUnrelatedNamesAreNotAsked() {
        let ps = projects(["Calc homework", "Lab report on pendulums", "Quarterly review deck"])
        XCTAssertTrue(ProjectMatch.similar(to: "Essay on sleep", in: ps).isEmpty)
        XCTAssertTrue(ProjectMatch.similar(to: "Read chapter 3", in: ps).isEmpty)
        XCTAssertTrue(ProjectMatch.similar(to: "ab", in: ps).isEmpty, "too short to say anything")
    }

    func testTheNewestProjectWinsATie() {
        let ps = projects(["Essay draft two", "Essay draft one"])   // newest first, as the store keeps them
        XCTAssertEqual(ProjectMatch.similar(to: "essay draft", in: ps).first?.name, "Essay draft two")
    }

    // MARK: the store

    func testLookingUpANameNeverCreatesAProject() {
        let store = DataStore()
        _ = store.addProject(name: "Calc homework")
        XCTAssertNil(store.existingProject(named: "Calc homew"))
        XCTAssertNil(store.existingProject(named: "Calc"))
        XCTAssertEqual(store.projects.count, 1, "typing must not make projects")
        XCTAssertEqual(store.existingProject(named: "calc HOMEWORK")?.name, "Calc homework")
        XCTAssertEqual(store.projectNamed("calc homework").name, "Calc homework", "starting reuses it")
        XCTAssertEqual(store.projects.count, 1)
    }

    func testTheStartCardHintDoesNotCreateProjectsWhileYouType() {
        // The hint used to call projectNamed(...) from the view body, which made a project for every keystroke.
        let src = try! String(contentsOfFile: #filePath.replacingOccurrences(of: "Tests/FocusUITests/ProjectMatchTests.swift", with: "Sources/FocusUI/Views/TodayIdle.swift"), encoding: .utf8)
        XCTAssertFalse(src.contains("projectNamed"), "views must not create projects")
    }

    func testCleanupRemovesTypingLeftoversAndNothingElse() {
        let store = DataStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func add(_ name: String, _ at: Double, _ edit: (inout Project) -> Void = { _ in }) {
            var p = store.addProject(name: name); p.createdAt = t0.addingTimeInterval(at); edit(&p); store.update(p)
        }
        for (i, n) in ["f", "fd", "fdf", "fdfa", "fdfad"].enumerated() { add(n, Double(i)) }       // one project per keystroke
        add("Essay", 10_000)                                                                        // a real, older, empty project
        add("Essay on sleep", 10_060) { $0.nextStep = "Outline" }                                   // typed a minute later, holds something
        add("Thesis", 20_000) { $0.context = "Chapter 3" }; add("Thesis chapter 3", 20_005)         // the shorter one holds a description
        XCTAssertEqual(store.removeTypingLeftovers(), 5, "f, fd, fdf, fdfa and the Essay prefix")
        let names = Set(store.projects.map(\.name))
        XCTAssertEqual(names, ["fdfad", "Essay on sleep", "Thesis", "Thesis chapter 3"])
        XCTAssertEqual(store.removeTypingLeftovers(), 0, "and it is safe to run again")
    }

    func testCleanupLeavesAnOldShortProjectAloneWhenTheLongerOneCameMuchLater() {
        let store = DataStore()
        var a = store.addProject(name: "Essay"); a.createdAt = Date(timeIntervalSince1970: 1_000)
        var b = store.addProject(name: "Essay on sleep"); b.createdAt = Date(timeIntervalSince1970: 1_000 + 86_400)
        store.update(a); store.update(b)
        XCTAssertEqual(store.removeTypingLeftovers(), 0)
    }
}

final class StoreFileSafetyTests: XCTestCase {
    @MainActor func testTheStoreFileIsPrivateAndAFailedSaveIsReported() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("focus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("store.json")
        let store = DataStore(url: url)
        _ = store.addProject(name: "Calc homework")
        XCTAssertFalse(store.saveFailed)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600, "only this user reads task and project names")

        try FileManager.default.removeItem(at: dir)                      // the folder is gone: a save cannot land
        _ = store.addProject(name: "Essay")
        XCTAssertTrue(store.saveFailed, "said out loud, not swallowed")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store.retrySave()
        XCTAssertFalse(store.saveFailed)
    }
}
