import XCTest
@testable import FocusUI
@testable import FocusJudge

/// Developer probe, only with FOCUS_PROBE=1: prints what each judge says about realistic windows, so a complaint like
/// "it says not sure when I am clearly off task" can be looked at with the real model. Not an accuracy measurement.
///   FOCUS_PROBE=1 swift test --filter JudgeProbeTests
final class JudgeProbeTests: XCTestCase {
    static let cases: [(String, Moment)] = [
        ("weather", Moment(task: "Writing a lab report in TextEdit", app: "Weather", windowTitle: "Weather")),
        ("youtube cats", Moment(task: "Writing a lab report in TextEdit", app: "Google Chrome", windowTitle: "Funniest cat videos 2026 - YouTube", url: "https://youtube.com/watch?v=abc")),
        ("netflix", Moment(task: "Finish the quarterly budget spreadsheet", app: "Safari", windowTitle: "Stranger Things - Netflix", url: "https://netflix.com/watch/1")),
        ("reddit funny", Moment(task: "Fix the pagination bug in the orders API", app: "Google Chrome", windowTitle: "r/funny - Reddit", url: "https://reddit.com/r/funny")),
        ("espn", Moment(task: "Study organic chemistry", app: "Google Chrome", windowTitle: "NBA scores and highlights - ESPN", url: "https://espn.com/nba")),
        ("amazon", Moment(task: "Write the methods section of my chemistry lab report", app: "Safari", windowTitle: "Amazon.com: Nike Air Max sneakers", url: "https://amazon.com/s?k=sneakers")),
        ("steam game", Moment(task: "Prepare slides for Monday's pitch", app: "Steam", windowTitle: "Counter-Strike 2")),
        ("tiktok", Moment(task: "Prepare slides for Monday's pitch", app: "Google Chrome", windowTitle: "TikTok - Make Your Day", url: "https://tiktok.com/foryou")),
        ("slope game (owner screenshot)", Moment(task: "Creating a resume", app: "Comet", windowTitle: "Slope Game - Comet - School", url: "https://slopeio.org")),
        ("on task docs", Moment(task: "Fix the pagination bug in the orders API", app: "Google Chrome", windowTitle: "Pagination - Django REST framework", url: "https://django-rest-framework.org/api-guide/pagination/")),
    ]

    func testPrint() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FOCUS_PROBE"] == "1", "set FOCUS_PROBE=1")
        guard DefaultJudge.status() == .ready else { throw XCTSkip("model unavailable") }
        let judge = DefaultJudge.make()
        for (name, m) in Self.cases {
            let prompt = Prompts.prompt(for: m)
            let a = await judge.reasonFirst(prompt: prompt)
            let b = await judge.relation(prompt: prompt)
            let j = await Pipeline.judge(m, with: judge)
            print("PROBE \(name): v1=\(a.label.rawValue) [\(a.reason)] | v2=\(b.relation ?? "-") [\(b.reason)] -> \(j.label.rawValue) (stage \(j.stage.rawValue))")
        }
    }
}
