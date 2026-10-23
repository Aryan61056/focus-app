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
        XCTAssertNil(c.banner, "answered, the question goes, and the reminder does not take its place")
    }

    /// The click is not evidence, so the brain is still "interrupted" until the next window read. Every way back must put the reminder
    /// away, or it asks "Back to ...?" over the task window you just went back to.
    func testEveryWayBackPutsTheReminderAway() async {
        for way in ["menu bar or notch", "shield", "banner"] {
            t = 0
            let c = make()
            await advance(c, to: 20)
            c.windowChanged(video)
            while c.presence.state != "interrupted" && t < 300 { await advance(c, to: t + 1) }
            XCTAssertEqual(c.banner?.kind, .reminder, way)
            switch way {
            case "shield":
                while c.shield == nil && t < 600 { await advance(c, to: t + 1) }
                XCTAssertEqual(c.shield?.kind, .pause, way)
                XCTAssertNil(c.banner, "the shield covers everything, so no banner under it")
                c.shieldBackToTask()
            case "banner": c.bannerBackToTask()
            default: c.act(.backToTask)
            }
            XCTAssertEqual(c.presence.state, "interrupted", "not evidence: the next window read decides")
            XCTAssertNil(c.banner, "\(way): no reminder over the task you went back to")
            await advance(c, to: t + 2)
            XCTAssertNil(c.banner, "\(way): it stays away on the next ticks")
        }
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

/// Hiding Focus (Command-H, or Hide Others from another app) hid every panel with the main window: the notch, the banner, the gray and
/// the shield vanished for the rest of the session. Found 2026-10-16 when the demo's "hide" action left nothing to render.
@MainActor
final class PanelsSurviveHidingTests: XCTestCase {
    func testNoFloatingPanelHidesWithTheApp() {
        XCTAssertFalse(BannerPanel().canHide, "banner")
        XCTAssertFalse(ShieldPanel().canHide, "shield")
        XCTAssertFalse(VeilPanel().canHide, "gray")
        let c = SessionController(judge: CountingJudge { _ in Verdict(label: .onTask) }, store: DataStore(), prefs: noWords())
        XCTAssertFalse(NotchPanelController(controller: c).makePanel().canHide, "notch")
    }
}

/// The banner's panel must be as tall as what it shows, for every kind and after switching kinds (it used to fall to its 80 pt floor,
/// clipping the buttons, once the heads-up turned into the reminder: the hosting view's fittingSize is not the content's).
@MainActor
final class BannerSizeTests: XCTestCase {
    func testThePanelFitsEveryKindAndKeepsFittingAfterASwitch() async {
        var t = 0.0
        let c = SessionController(judge: CountingJudge { _ in Verdict(label: .onTask) }, store: DataStore(), prefs: noWords(), now: { t })
        c.windowChanged(WindowSnapshot(app: "Notes", title: "Calc homework"))
        c.begin(task: "Calc homework", preset: .standard, shadow: false)
        let b = BannerController(controller: c)
        b.start()
        var heights: [CGFloat] = []
        for kind in [Banner.Kind.early, .reminder, .checkIn, .early] {
            c.debugShowBanner(kind, at: t); t += 1
            await Task.yield(); b.refresh()
            heights.append(b.sizeForTesting.height)
        }
        b.stop()
        for h in heights { XCTAssertGreaterThan(h, 110, "title, a line of what Hushd saw and the buttons, plus the shadow margin") }
        XCTAssertEqual(heights.first!, heights.last!, accuracy: 0.5, "the same kind measures the same after other kinds")
        let long = SessionController(judge: CountingJudge { _ in Verdict(label: .onTask) }, store: DataStore(), prefs: noWords(), now: { t })
        long.windowChanged(WindowSnapshot(app: "Notes", title: "x"))
        long.begin(task: "Write the methods and results sections of the pendulum lab report for physics", preset: .standard, shadow: false)
        let lb = BannerController(controller: long); lb.start()
        long.debugShowBanner(.reminder, at: t); lb.refresh()
        XCTAssertGreaterThan(lb.sizeForTesting.height, heights[1] + 10, "a long task wraps to two lines and the panel grows")
        lb.stop()
    }
}
