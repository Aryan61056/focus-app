import XCTest
@testable import FocusUI

@MainActor final class ParkingLotTests: XCTestCase {
    func testEmptyTrimmedBoundedAndCompletedThoughts() {
        let store = DataStore()
        XCTAssertFalse(store.park(" \n ")); XCTAssertTrue(store.park("  Buy a synthetic notebook \n"))
        XCTAssertEqual(store.thoughts.first?.text, "Buy a synthetic notebook")
        XCTAssertFalse(store.park(String(repeating: "a", count: 2200)))
        XCTAssertTrue(store.park(String(repeating: "a", count: 2000)))
        store.completeThought(store.thoughts[0].id, completed: true); store.clearThoughts(completedOnly: true)
        XCTAssertEqual(store.thoughts.count, 1); store.deleteEverything(); XCTAssertTrue(store.thoughts.isEmpty)
    }
    func testLegacyStoreAndPersistence() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("store.json")
        try Data(#"{"version":1,"projects":[],"sessions":[],"review":[]}"#.utf8).write(to: url)
        let store = DataStore(url: url); XCTAssertTrue(store.thoughts.isEmpty)
        store.park("Synthetic reminder"); store.completeThought(store.thoughts[0].id, completed: true)
        let loaded = try XCTUnwrap(DataStore(url: url).thoughts.first)
        XCTAssertEqual(loaded.id, store.thoughts[0].id); XCTAssertEqual(loaded.text, store.thoughts[0].text)
        XCTAssertTrue(loaded.completed); XCTAssertEqual(loaded.createdAt.timeIntervalSince1970, store.thoughts[0].createdAt.timeIntervalSince1970, accuracy: 1)
        let export = try XCTUnwrap(store.exportJSON()); XCTAssertTrue(String(decoding: export, as: UTF8.self).contains("Synthetic reminder"))
    }
    func testFailedDiskWriteDoesNotPretendToSave() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("missing/store.json")
        let store = DataStore(url: url)
        XCTAssertFalse(store.park("A synthetic thought")); XCTAssertTrue(store.thoughts.isEmpty)
    }
    func testShortcutPreferencePersistsAndChoicesDoNotOverlapStart() throws {
        let name = "focus-parking-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Preferences(defaults: defaults); XCTAssertEqual(prefs.parkingShortcut, .controlOptionP)
        prefs.parkingShortcut = .commandControlP; XCTAssertEqual(Preferences(defaults: defaults).parkingShortcut, .commandControlP)
        XCTAssertEqual(Set(ParkingShortcut.allCases.map(\.keyCode)).count, 2)
        XCTAssertFalse(ParkingShortcut.allCases.contains { $0.key == "f" })
    }
}
