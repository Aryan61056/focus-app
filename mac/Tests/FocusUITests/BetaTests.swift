import XCTest
import FocusJudge
@testable import FocusUI

/// The beta program: build info, the local journal (unclean exits, pulses, limits), hang and crash reading, and the feedback report,
/// above all that a report never carries a task, project, title or screen word.
@MainActor
final class BetaTests: XCTestCase {
    var dirs: [URL] = []
    override func tearDown() { dirs.forEach { try? FileManager.default.removeItem(at: $0) }; dirs = [] }
    func folder() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("focus-beta-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); dirs.append(u); return u
    }

    // MARK: build

    func testBuildReadsBetaKeys() {
        let b = BetaBuild.from(info: ["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "7", "FocusChannel": "beta",
                                      "FocusBetaExpires": "2026-11-01", "FocusFeedbackAddress": " beta@example.org ",
                                      "FocusReleaseNotes": "# Beta 7\n- Faster start\n\n* Calmer nudges\nPlain line", "FocusBuildID": "x-abc"])
        XCTAssertEqual(b.label, "0.2.0 beta 7")
        XCTAssertEqual(b.tag, "Beta 7")
        XCTAssertEqual(b.feedbackAddress, "beta@example.org")
        XCTAssertEqual(b.notes, ["Faster start", "Calmer nudges", "Plain line"])
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let oct20 = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
        XCTAssertEqual(b.daysLeft(at: oct20, calendar: cal), 12)
        XCTAssertFalse(b.expired(at: oct20))
        XCTAssertTrue(b.expired(at: cal.date(from: DateComponents(year: 2026, month: 11, day: 2))!))
    }

    func testBuildWithoutKeysIsDevAndOddValuesAreIgnored() {
        let dev = BetaBuild.from(info: [:])
        XCTAssertEqual(dev.channel, .dev); XCTAssertTrue(dev.isTesting); XCTAssertNil(dev.expires); XCTAssertEqual(dev.label, "0.1.0 (dev)")
        let odd = BetaBuild.from(info: ["FocusChannel": "nightly", "FocusFeedbackAddress": "not an address", "FocusBetaExpires": "soon"])
        XCTAssertEqual(odd.channel, .dev); XCTAssertNil(odd.feedbackAddress); XCTAssertNil(odd.expires)
        XCTAssertFalse(BetaBuild(channel: .release).isTesting)
    }

    // MARK: journal

    func testUncleanExitIsNoticedOnTheNextLaunch() {
        let f = folder()
        let a = BetaJournal.standard(in: f)
        XCTAssertFalse(a.launched())
        // No quit: the process "crashed". The next launch reads the marker.
        let b = BetaJournal.standard(in: f)
        XCTAssertTrue(b.launched())
        XCTAssertNotNil(b.unacknowledgedExit)
        XCTAssertEqual(b.count(.uncleanExit), 1)
        b.quitCleanly()
        let c = BetaJournal.standard(in: f)
        XCTAssertFalse(c.launched())
        XCTAssertEqual(c.count(.launch), 3)
        XCTAssertEqual(c.count(.quit), 1)
        // Still waiting for the tester until they answer or dismiss it.
        XCTAssertNotNil(c.unacknowledgedExit)
        c.acknowledgeExit()
        XCTAssertNil(BetaJournal.standard(in: f).unacknowledgedExit)
    }

    func testRecordingOffWritesNothingAndTheLogIsBounded() {
        let j = BetaJournal()
        j.recording = false; j.note(.warning)
        XCTAssertTrue(j.events.isEmpty)
        j.recording = true
        for _ in 0..<(BetaJournal.limit + 25) { j.note(.sessionStart) }
        XCTAssertEqual(j.events.count, BetaJournal.limit)
        j.note(.hang, 2.345)
        XCTAssertEqual(j.events.last?.value, 2.3)
        j.clear()
        XCTAssertTrue(j.events.isEmpty)
    }

    func testJournalFileIsPrivateAndRoundTrips() throws {
        let f = folder()
        let j = BetaJournal.standard(in: f)
        j.note(.sessionEnd, 25); j.answerPulse(score: 4, note: "  fine  "); j.pulseOn = false
        let path = f.appendingPathComponent("beta.json").path
        let perms = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        let k = BetaJournal.standard(in: f)
        XCTAssertEqual(k.count(.sessionEnd), 1)
        XCTAssertEqual(k.pulses.first?.note, "fine")
        XCTAssertFalse(k.pulseOn)
    }

    func testPulseIsWeeklyBetweenSessionsAfterRealUse() {
        let j = BetaJournal()
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        j.now = { now }
        XCTAssertFalse(j.pulseDue(sessionsFinished: 2, sessionActive: false))
        XCTAssertFalse(j.pulseDue(sessionsFinished: 3, sessionActive: true))
        XCTAssertTrue(j.pulseDue(sessionsFinished: 3, sessionActive: false))
        j.answerPulse(score: 9)
        XCTAssertEqual(j.pulses.last?.score, 5)
        now += 6 * 86400
        XCTAssertFalse(j.pulseDue(sessionsFinished: 10, sessionActive: false))
        now += 86400
        XCTAssertTrue(j.pulseDue(sessionsFinished: 10, sessionActive: false))
        j.skipPulse()
        XCTAssertFalse(j.pulseDue(sessionsFinished: 10, sessionActive: false))
        j.pulseOn = false; now += 30 * 86400
        XCTAssertFalse(j.pulseDue(sessionsFinished: 10, sessionActive: false))
    }

    func testNotesShowOncePerBuild() {
        let j = BetaJournal()
        let b3 = BetaBuild(build: "3", channel: .beta, notes: ["x"]), b4 = BetaBuild(build: "4", channel: .beta, notes: ["y"])
        XCTAssertTrue(j.notesUnseen(for: b3)); j.markNotesSeen(for: b3)
        XCTAssertFalse(j.notesUnseen(for: b3)); XCTAssertTrue(j.notesUnseen(for: b4))
        XCTAssertFalse(j.notesUnseen(for: BetaBuild(build: "5", channel: .beta)))
    }

    // MARK: hangs and crashes

    func testHangNeedsTwoSecondsAndIgnoresSleep() {
        let t = Date(timeIntervalSince1970: 0)
        XCTAssertNil(HangWatch.hang(last: t, now: t.addingTimeInterval(0.6)))
        XCTAssertNil(HangWatch.hang(last: t, now: t.addingTimeInterval(2.4)))
        XCTAssertEqual(HangWatch.hang(last: t, now: t.addingTimeInterval(3.0)) ?? 0, 2.5, accuracy: 0.001)
        XCTAssertNil(HangWatch.hang(last: t, now: t.addingTimeInterval(600)))
    }

    static let ips = """
    {"app_name":"focus-app","timestamp":"2026-10-17 14:02:11.00 +0000","app_version":"0.1.0","os_version":"macOS 27.0 (27A123)","bug_type":"309","incident_id":"ABC-123"}
    {"crashReporterKey":"SECRET-KEY","procPath":"/Users/sam/Applications/Focus.app/Contents/MacOS/focus-app","faultingThread":1,
     "exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},"termination":{"indicator":"Trace/BPT trap: 5"},
     "asi":{"libswiftCore.dylib":["Fatal error: Calc homework secret"]},
     "usedImages":[{"name":"focus-app","path":"/Users/sam/Applications/Focus.app/Contents/MacOS/focus-app"},{"name":"libswiftCore.dylib","path":"/usr/lib/swift/libswiftCore.dylib"}],
     "threads":[{"frames":[{"imageIndex":0,"imageOffset":10}]},
                {"triggered":true,"frames":[{"imageIndex":1,"symbol":"_assertionFailure(_:_:file:line:flags:)"},{"imageIndex":0,"symbol":"SessionController.tick()"},{"imageIndex":0,"imageOffset":4096},{"imageIndex":0,"symbol":"load /Users/sam/Library/x.swift"}]}]}
    """

    func testCrashSummaryKeepsCodeAndDropsEverythingPersonal() throws {
        let s = try XCTUnwrap(CrashReports.summary(ips: Self.ips))
        XCTAssertEqual(s.exception, "EXC_BREAKPOINT"); XCTAssertEqual(s.signal, "SIGTRAP"); XCTAssertEqual(s.termination, "Trace/BPT trap: 5")
        XCTAssertEqual(s.frames, ["libswiftCore.dylib _assertionFailure(_:_:file:line:flags:)", "focus-app SessionController.tick()", "focus-app 0x1000", "focus-app load x.swift"])
        XCTAssertNotNil(s.when)
        let text = String(data: try JSONEncoder().encode(s), encoding: .utf8)!
        for leak in ["/Users", "sam", "SECRET-KEY", "ABC-123", "Calc homework"] { XCTAssertFalse(text.contains(leak), leak) }
        XCTAssertNil(CrashReports.summary(ips: "not a report"))
    }

    func testLatestCrashIsTheNewestOfThisApp() throws {
        let f = folder(), fm = FileManager.default
        for (name, age) in [("focus-app-2026-10-10.ips", 86400.0 * 8), ("focus-app-2026-10-17.ips", 3600.0), ("Safari-2026-10-18.ips", 10.0), ("focus-app-notes.txt", 5.0)] {
            let u = f.appendingPathComponent(name); try Data("x".utf8).write(to: u)
            try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: u.path)
        }
        XCTAssertEqual(CrashReports.latest(in: f, since: Date().addingTimeInterval(-86400 * 14))?.lastPathComponent, "focus-app-2026-10-17.ips")
        XCTAssertNil(CrashReports.latest(in: f, since: Date().addingTimeInterval(-60)))
        XCTAssertNil(CrashReports.latest(in: f.appendingPathComponent("missing"), since: .distantPast))
    }

    // MARK: the report

    func secretStore() -> DataStore {
        let s = DataStore()
        let p = s.addProject(name: "Secret Project Zebra")
        var q = p; q.context = "secret context words"; s.update(q)
        s.record(SessionRecord(projectId: p.id, task: "Calc homework secret", timed: false, start: Date().addingTimeInterval(-3600), end: Date(),
                               activeSeconds: 1800, offTopicSeconds: 120, unsureSeconds: 60, drifts: 2, interrupts: 1, refusals: 0, shadowMarks: 0,
                               segments: [], reads: { var r = ReadStats(); r.model = 4; r.offTask = 1; r.onTask = 3; return r }()))
        s.record(SessionRecord(projectId: p.id, task: "old", timed: true, start: Date().addingTimeInterval(-86400 * 30), end: Date().addingTimeInterval(-86400 * 30 + 600),
                               activeSeconds: 600, offTopicSeconds: 0, unsureSeconds: 0, drifts: 0, interrupts: 0, refusals: 0, shadowMarks: 0, segments: []))
        s.addReview(ReviewMoment(sessionId: nil, projectId: p.id, at: Date(), windowKey: "safari|secret window title", siteKey: "secretsite.example", reason: "secret reason"))
        s.addReview(ReviewMoment(sessionId: nil, projectId: p.id, at: Date(), windowKey: "notes|answered", siteKey: "notes"))
        s.answerReview(s.review[0].id, "right")
        s.park("secret parked thought")
        return s
    }

    func testReportCarriesNoTaskProjectTitleOrScreenText() throws {
        let store = secretStore()
        let prefs = Preferences(defaults: UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!)
        prefs.neverJudgedApps = ["SecretMessenger"]; prefs.notchNote = "secret notch line"; prefs.friendName = "Secret Name"
        let j = BetaJournal(); j.note(.sessionStart); j.note(.warning); j.answerPulse(score: 3)
        var d = FeedbackDraft(kind: .wrongCall); d.message = "It called my notes off task."
        let r = FeedbackBuilder.make(d, build: BetaBuild(build: "3", channel: .beta), system: FeedbackBuilder.system(judge: .ready, windowAccess: .allowed, screen: .unknown),
                                     prefs: prefs, store: store, journal: j, crash: CrashReports.summary(ips: Self.ips))
        let text = String(data: try XCTUnwrap(r.encoded()), encoding: .utf8)!
        for leak in ["Secret Project", "secret context", "Calc homework", "secret window", "secretsite", "secret reason", "parked thought",
                     "SecretMessenger", "secret notch", "Secret Name", "/Users"] {
            XCTAssertFalse(text.contains(leak), "report leaked \(leak)")
        }
        XCTAssertTrue(text.contains("It called my notes off task."))
        let u = try XCTUnwrap(r.usage)
        XCTAssertEqual(u.sessions, 2); XCTAssertEqual(u.sessionsLast14Days, 1); XCTAssertEqual(u.activeMinutesLast14Days, 30)
        XCTAssertEqual(u.reviewAnswered, 1); XCTAssertEqual(u.reviewAgreed, 1); XCTAssertEqual(u.projectsDescribed, 1)
        XCTAssertEqual(r.settings?["neverJudgedCount"], "1")
        XCTAssertEqual(r.events?.map(\.kind), [.sessionStart, .warning, .pulseAnswered])
    }

    func testUncheckedSectionsAreLeftOut() throws {
        var d = FeedbackDraft(); d.message = "x"
        d.includeSystem = false; d.includeUsage = false; d.includeEvents = false; d.includeCrash = false
        d.contact = "   "
        let j = BetaJournal(); j.note(.launch)
        let r = FeedbackBuilder.make(d, build: BetaBuild(), system: FeedbackBuilder.system(judge: .unknown, windowAccess: .unknown, screen: .unknown),
                                     prefs: Preferences(defaults: UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!), store: secretStore(),
                                     journal: j, crash: CrashReports.summary(ips: Self.ips))
        XCTAssertNil(r.system); XCTAssertNil(r.settings); XCTAssertNil(r.usage); XCTAssertNil(r.events); XCTAssertNil(r.pulses); XCTAssertNil(r.crash); XCTAssertNil(r.contact)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(r.encoded())) as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["schema", "id", "created", "kind", "message", "app"])
    }

    func testMessageIsTrimmedAndCapped() {
        var d = FeedbackDraft(); d.message = "  " + String(repeating: "a", count: 5000) + "  "
        XCTAssertTrue(d.ready)
        let r = FeedbackBuilder.make(d, build: BetaBuild(), system: nil, prefs: nil, store: nil, journal: nil, crash: nil)
        XCTAssertEqual(r.message.count, FeedbackReport.messageLimit)
        XCTAssertFalse(FeedbackDraft().ready)
        XCTAssertTrue(r.fileName.hasPrefix("focus-feedback-")); XCTAssertTrue(r.fileName.hasSuffix(".json"))
    }

    /// The Swift report and tools/beta/feedback.py agree on the shape: every key the app writes is one the triage tool's fixture has.
    func testReportShapeMatchesTheTriageToolFixture() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("tools/beta/fixtures/sample-report.json")
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        let j = BetaJournal(); j.note(.hang, 2.5); j.answerPulse(score: 4)
        var d = FeedbackDraft(); d.message = "x"; d.contact = "me"
        let r = FeedbackBuilder.make(d, build: BetaBuild(buildID: "id", channel: .beta), system: FeedbackBuilder.system(judge: .ready, windowAccess: .allowed, screen: .allowed),
                                     prefs: Preferences(defaults: UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!), store: secretStore(),
                                     journal: j, crash: CrashReports.summary(ips: Self.ips))
        let mine = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(r.encoded())) as? [String: Any])
        func keys(_ o: Any?) -> Set<String> { Set((o as? [String: Any])?.keys.map { $0 } ?? []) }
        XCTAssertEqual(keys(mine), keys(fixture))
        for k in ["app", "system", "usage", "crash"] { XCTAssertEqual(keys(mine[k]), keys(fixture[k]), k) }
        XCTAssertEqual(keys((mine["usage"] as? [String: Any])?["reads"]), keys((fixture["usage"] as? [String: Any])?["reads"]))
        XCTAssertTrue(keys((mine["events"] as? [Any])?.first).isSubset(of: ["at", "kind", "value"]))
        XCTAssertEqual(mine["schema"] as? String, fixture["schema"] as? String)
        XCTAssertEqual(Set(BetaEventKind.allCases.map(\.rawValue)).count, BetaEventKind.allCases.count)
    }

    // MARK: missions and the controller

    func testMissionsTickFromWhatIsAlreadyThere() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "focus.tests.\(UUID().uuidString)")!)
        let j = BetaJournal()
        XCTAssertEqual(BetaMission.all(store: DataStore(), prefs: prefs, journal: j).filter(\.done).count, 0)
        j.note(.backToTask, 1); j.note(.feedbackSaved)
        let done = Set(BetaMission.all(store: secretStore(), prefs: prefs, journal: j).filter(\.done).map(\.id))
        XCTAssertEqual(done, ["first", "long", "describe", "back", "review", "feedback"])
    }

    func testControllerWritesSessionsAndRefusalsToTheJournal() async {
        var t = 0.0
        let store = DataStore()
        let c = SessionController(judge: ScriptedJudge(markers: []), store: store, now: { t })
        let j = BetaJournal(); c.beta = BetaCenter(build: BetaBuild(channel: .beta), journal: j)
        c.setJudgeStatus(.unavailable("off"))
        c.begin(task: "Write")
        t = 120; c.end()
        XCTAssertEqual(j.events.map(\.kind), [.judgeUnavailable, .sessionStart, .sessionEnd])
        XCTAssertEqual(j.events.last?.value, 2)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testSavingAReportCountsAndClearsTheCrashNotice() throws {
        let f = folder()
        let j = BetaJournal.standard(in: f); j.launched()
        let k = BetaJournal.standard(in: f); k.launched()
        let center = BetaCenter(build: BetaBuild(channel: .beta), journal: k)
        XCTAssertTrue(center.crashNoticeDue)
        var d = FeedbackDraft(); d.message = "crashed"
        let r = FeedbackBuilder.make(d, build: center.build, system: nil, prefs: nil, store: nil, journal: k, crash: nil)
        let out = f.appendingPathComponent(r.fileName)
        XCTAssertTrue(center.save(r, to: out))
        XCTAssertFalse(center.crashNoticeDue)
        XCTAssertEqual(k.count(.feedbackSaved), 1)
        let back = try JSONDecoder.store.decode(FeedbackReport.self, from: Data(contentsOf: out))
        XCTAssertEqual(back.id, r.id)
        XCTAssertFalse(center.save(r, to: f.appendingPathComponent("missing/dir/x.json")))
    }
}
