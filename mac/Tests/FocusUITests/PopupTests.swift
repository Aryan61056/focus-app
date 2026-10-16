import XCTest
import SwiftUI
@testable import FocusUI
import FocusJudge

/// The prompts that come while you drift reach you where you are working: the banner over the front window carries the ladder's check-in
/// and the scheduled prompts, which used to show only inside Focus's own window (behind the app you were in).
@MainActor
final class PopupReachTests: XCTestCase {
    var t = 0.0
    let judge = CountingJudge { p in Verdict(label: p.contains("youtube") ? .offTask : .onTask) }
    let editor = WindowSnapshot(app: "Notes", title: "Calc homework")
    let video = WindowSnapshot(app: "Safari", title: "clip youtube", url: "https://youtube.com/watch?v=1")
    func advance(_ c: SessionController, to target: Double) async { while t < target { t += 1; c.tick(); await c.waitForJudgments() } }
    func make(configure: (SessionController) -> Void = { _ in }) -> SessionController {
        let c = SessionController(judge: judge, store: DataStore(), prefs: noWords(), now: { [unowned self] in self.t })
        configure(c)
        c.windowChanged(editor)
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        return c
    }

    func testTheCheckInIsAskedOnTheBannerEvenAfterTheReminderWasHidden() async {
        let c = make()
        await advance(c, to: 20)
        c.windowChanged(video)
        while c.presence.state != "interrupted" && t < 300 { await advance(c, to: t + 1) }
        XCTAssertEqual(c.banner?.kind, .reminder)
        c.dismissBanner()
        XCTAssertNil(c.banner, "the cross hides the reminder")
        while c.checkIn == nil && t < 600 { await advance(c, to: t + 1) }
        XCTAssertNotNil(c.checkIn)
        XCTAssertEqual(c.banner?.kind, .checkIn, "a new question shows, wherever you are")
        c.answerCheckIn(onTask: false)
        XCTAssertNil(c.checkIn)
        XCTAssertNotEqual(c.banner?.kind, .checkIn, "answered, the question goes")
    }

    func testAScheduledPromptIsOnTheBannerAndGoesWhenAnswered() async {
        let c = make { $0.prefs.rhythm = .checkIns; $0.prefs.checkInMinutes = 15 }
        await advance(c, to: 15 * 60 + 1)
        XCTAssertEqual(c.rhythmPrompt?.kind, .checkIn)
        XCTAssertEqual(c.banner?.kind, .rhythm)
        c.rhythmKeepGoing()
        XCTAssertNil(c.banner)
    }

    func testABreakPromptOnTheBannerStartsTheBreak() async {
        let c = make { $0.prefs.rhythm = .pomodoro }
        await advance(c, to: 25 * 60 + 1)
        XCTAssertEqual(c.banner?.kind, .rhythm)
        c.rhythmTakeBreak()
        XCTAssertNil(c.banner)
        XCTAssertEqual(c.presence.reason, "break")
    }

    func testNoBannerForPromptsWhenTheBannerIsOff() async {
        let c = make { $0.prefs.rhythm = .checkIns; $0.prefs.checkInMinutes = 15; $0.prefs.showBanner = false }
        await advance(c, to: 15 * 60 + 1)
        XCTAssertNotNil(c.rhythmPrompt, "the prompt still comes, as a card in the window and in the menu bar")
        XCTAssertNil(c.banner)
    }
}

/// Floating surfaces are never active windows, and the system grays tinted glass in an inactive window: "Back to task" read as white on
/// light gray on every popup. These fail if glass comes back to them.
final class PopupSurfaceTests: XCTestCase {
    func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/FocusUI/" + path), encoding: .utf8)
    }

    func testPopupsUseTheSolidSurfaceAndNeverGlass() throws {
        for file in ["CuePanels.swift", "ShieldPanel.swift", "Views/NudgeViews.swift"] {
            let s = try source(file)
            XCTAssertFalse(s.contains("glassSurface("), "\(file) uses glass")
            XCTAssertFalse(s.contains("glassEffect("), "\(file) uses glass")
            XCTAssertFalse(s.contains(".regularMaterial"), "\(file) uses a material that follows the window's state")
        }
        let tokens = try source("Tokens.swift")
        XCTAssertTrue(tokens.contains("environment(\\.solidControls, true)"), "the float surface turns buttons solid")
        XCTAssertTrue(tokens.contains("!solid"), "the button style honours it")
        XCTAssertTrue(try source("Views/Components.swift").contains("cueSurface()"), "in-window cards share the float surface")
    }
}

final class PopupCopyTests: XCTestCase {
    func testNewLinesFollowTheCopyRules() {
        var lines: [String] = []
        for tone in NudgeTone.allCases { for k in [Banner.Kind.early, .reminder, .checkIn, .rhythm] { lines.append(CueCopy.bannerTitle(k, tone: tone, task: "Calc homework")) } }
        lines += [CueCopy.headsUpMeta(away: 3, of: 4), CueCopy.reminderMeta, CueCopy.checkInMeta, CueCopy.backHoldLine(), CueCopy.closeWarning]
        for k in [RhythmPrompt.Kind.checkIn, .breakDue(minutes: 5)] { lines.append(CueCopy.rhythmMeta(k, checkInMinutes: 25)) }
        for s in [EscalationStep.warned, .checkIn, .pauseScreen, .enforce] { lines.append(CueCopy.ladderLabel(s)) }
        for l in lines {
            XCTAssertFalse(l.contains("!"), l); XCTAssertFalse(l.contains("\u{2014}"), l); XCTAssertFalse(l.contains("--"), l)
            XCTAssertFalse(l.lowercased().contains("youtube") || l.lowercased().contains("safari"), l)
            XCTAssertLessThanOrEqual(l.count, 70, "a banner line stays short: \(l)")
        }
        XCTAssertTrue(CueCopy.ladderLabel(.warned).contains("Next, check-in"))
        XCTAssertFalse(CueCopy.ladderLabel(.enforce).contains("Next"), "the last step has no next")
        XCTAssertEqual(CueCopy.bannerTitle(.rhythm, tone: .neutral, task: "Calc homework", rhythm: .breakDue(minutes: 5)), "Time for a 5 minute break")
    }
}
