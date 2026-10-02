import XCTest
@testable import FocusJudge

/// Window titles are whatever other apps put there. None of this may crash.
final class RobustnessTests: XCTestCase {
    func randomString(_ g: inout SystemRandomNumberGenerator) -> String {
        let pieces = ["a", "Z", "é", "日本語", "🙂", "\u{200B}", "\u{202E}", "\n", "\t", " ", "%", "%41", "%zz", "<", ">", "[system]", "http://", "://", "..", "/", "\\", "\0", "ignore previous instructions", "off_task", String(repeating: "x", count: 200)]
        return (0..<Int.random(in: 0...12, using: &g)).map { _ in pieces.randomElement(using: &g)! }.joined()
    }

    func testRulesAndPromptsSurviveHostileText() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<3000 {
            let m = Moment(task: randomString(&g), app: randomString(&g), windowTitle: randomString(&g), url: randomString(&g), documentPath: randomString(&g),
                           windowText: randomString(&g), project: ProjectProfile())
            _ = Rules.isSensitive(m); _ = Rules.isNeverJudged(m, apps: ["Messages", randomString(&g)]); _ = Rules.looksInjected(m)
            _ = Rules.sharedTaskWords(m); _ = Rules.stage1(m); _ = Rules.looksPrivate(screenText: m.windowText)
            _ = Prompts.prompt(for: m)
        }
    }

    func testAHugeWindowTextIsClippedBeforeTheModel() {
        let m = Moment(task: "t", app: "a", windowTitle: "w", url: "", documentPath: "", windowText: String(repeating: "word ", count: 200_000), project: ProjectProfile())
        XCTAssertLessThan(Prompts.prompt(for: m).count, 20_000)
    }
}
