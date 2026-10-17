import XCTest
@testable import FocusJudge

final class StuckQualityTests: XCTestCase {
    func testTenSyntheticTasksWithTheRealSystemModel() async throws {
        guard ProcessInfo.processInfo.environment["FOCUS_STUCK_QUALITY"] == "1" else { throw XCTSkip("opt-in local model quality check") }
        guard #available(macOS 26.0, *), case .available = AppleJudge.availability else { throw XCTSkip("system model unavailable") }
        let cases = [
            ("Essay on Hamlet", "Argue whether Hamlet delays through doubt; use the To be or not to be speech."),
            ("Study chemistry", "Equilibrium constants; distinguish Q from K and predict reaction shifts."),
            ("Fix duplicate rows", "SwiftUI list duplicates after refresh; requests may complete out of order."),
            ("Read biology chapter", "Photosynthesis: compare the light-dependent reactions and Calvin cycle."),
            ("Calc homework", "Use integration by parts to integrate x times e to the x."),
            ("History essay", "Compare two primary-source accounts of the Boston Tea Party."),
            ("Design settings", "A Mac focus app needs a clear grouped settings form for nudge intensity."),
            ("Practice Spanish", "Choose preterite versus imperfect when describing yesterday's trip."),
            ("Recycling presentation", "Explain how contamination affects the school's paper recycling."),
            ("Friction lab report", "Compare measured friction for a wooden block on three synthetic surfaces.")
        ]
        var markdown = "# I'm stuck: model quality check\n\nReal Apple system model, synthetic task/context only. Prompt: `core/prompts/stuck_v1.txt`. Raw guided-generation strings below; no screen data. These ten examples are a development quality check, not an accuracy measurement.\n"
        for (task, context) in cases {
            let raw = await AppleAssistant().rawNextActions(task: task, context: context)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = String(data: try encoder.encode(raw), encoding: .utf8)!
            markdown += "\n## \(task)\n\nContext: \(context)\n\n```json\n\(json)\n```\n"
            XCTAssertNotNil(raw, "model refused or failed for \(task)")
        }
        if let path = ProcessInfo.processInfo.environment["FOCUS_STUCK_OUTPUT"] { try markdown.write(toFile: path, atomically: true, encoding: .utf8) }
    }
}
