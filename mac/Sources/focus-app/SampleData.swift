import Foundation
import FocusUI

/// Developer tool, only with FOCUS_DEMO=1 and FOCUS_DEMO_SAMPLE=1: fills the in-memory demo store with two weeks of made-up projects and
/// sessions, so the filled states of Projects, History and Insights can be rendered and designed. Synthetic data, never the real store.
@MainActor
enum SampleData {
    static func seedIfRequested(_ store: DataStore?) {
        let env = ProcessInfo.processInfo.environment
        guard env["FOCUS_DEMO"] == "1", env["FOCUS_DEMO_SAMPLE"] == "1", let store, store.sessions.isEmpty else { return }
        var thesis = store.addProject(name: "Thesis chapter 3")
        thesis.context = "Writing the methods chapter: sampling, survey design, and the analysis plan. Zotero and the stats docs count."
        thesis.nextStep = "Tighten the sampling paragraph"
        store.update(thesis)
        var calc = store.addProject(name: "Calc homework")
        calc.context = "Problem set 6, integration by parts. Khan Academy and the course site count."
        store.update(calc)
        var deck = store.addProject(name: "Quarterly review deck")
        deck.nextStep = "Charts for slide 4"
        store.update(deck)

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // (days ago, start hour, minutes, project, drifts)
        let plan: [(Int, Double, Double, Project, Int)] = [
            (0, 9.25, 52, thesis, 1), (0, 11, 38, calc, 0), (0, 14.5, 25, deck, 2),
            (1, 9.5, 64, thesis, 1), (1, 13, 41, deck, 0),
            (2, 10, 55, thesis, 2), (3, 8.75, 47, calc, 0), (3, 15, 30, thesis, 1),
            (4, 9, 70, thesis, 0), (6, 10.5, 35, deck, 1), (7, 9.25, 58, thesis, 1),
            (8, 14, 44, calc, 3), (9, 9.5, 61, thesis, 0), (10, 11, 33, deck, 1), (12, 9, 50, thesis, 1),
        ]
        for (i, p) in plan.enumerated().reversed() {
            let start = today.addingTimeInterval(-Double(p.0) * 86_400 + p.1 * 3600)
            let total = p.2 * 60
            let off = Double(p.4) * 150, unsure = Double((i % 3) + 1) * 60
            let segs: [TimelineSegment] = p.4 == 0
                ? [.init(.on, total * 0.45), .init(.unsure, unsure), .init(.on, total * 0.55 - unsure)]
                : [.init(.on, total * 0.4), .init(.off, off * 0.6), .init(.on, total * 0.25), .init(.unsure, unsure), .init(.off, off * 0.4), .init(.on, total * 0.35 - off - unsure)]
            var reads = ReadStats(); reads.onTask = Int(total / 40); reads.unsure = Int(unsure / 30); reads.offTask = p.4 * 3; reads.model = reads.total / 2; reads.rule = reads.total - reads.model
            store.record(SessionRecord(projectId: p.3.id, task: p.3.name, timed: i % 4 == 0, start: start, end: start.addingTimeInterval(total),
                                       activeSeconds: total, offTopicSeconds: off, unsureSeconds: unsure, drifts: p.4, interrupts: p.4, refusals: 0,
                                       shadowMarks: 0, segments: segs, reads: reads, returns: p.4 == 0 ? nil : Array(repeating: 40 + Double(i * 7 % 50), count: p.4)))
        }
    }
}
