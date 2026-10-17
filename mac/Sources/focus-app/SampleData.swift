import Foundation
import FocusUI
import SwiftUI

/// Developer tool, only with FOCUS_DEMO=1 and FOCUS_DEMO_SAMPLE=1: fills the in-memory demo store with two weeks of made-up projects and
/// sessions, so the filled states of Projects, History and Insights can be rendered and designed. Synthetic data, never the real store.
@MainActor
enum SampleData {
    static func seedIfRequested(_ store: DataStore?) {
        let env = ProcessInfo.processInfo.environment
        guard env["FOCUS_DEMO"] == "1", env["FOCUS_DEMO_SAMPLE"] == "1", let store, store.sessions.isEmpty else { return }
        var thesis = store.addProject(name: "Thesis chapter 3")
        thesis.context = "Writing the methods chapter: sampling, survey design, and the analysis plan. Zotero and the stats docs count."
        store.update(thesis)
        var calc = store.addProject(name: "Calc homework")
        calc.context = "Problem set 6, integration by parts. Khan Academy and the course site count."
        store.update(calc)
        let deck = store.addProject(name: "Quarterly review deck")

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
            // Run just after midnight, "today" would be in the future; keep every made-up session in the past.
            let base = today.addingTimeInterval(-Double(p.0) * 86_400 + p.1 * 3600)
            let start = base > .now ? base.addingTimeInterval(-86_400) : base
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

/// Developer tool, only with FOCUS_DEMO=1 and FOCUS_DEMO_PREVIEW=1: turns screen reading on and feeds the controller a drawn, made-up
/// picture of the demo's front window every 3 seconds, so the picture frame on Today can be rendered without capturing any real screen.
@MainActor
enum DemoPreview {
    static func startIfRequested(_ c: SessionController) {
        let env = ProcessInfo.processInfo.environment
        guard env["FOCUS_DEMO"] == "1", env["FOCUS_DEMO_PREVIEW"] == "1" else { return }
        c.prefs.readScreen = true
        c.setPreviewAccess(.allowed)
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated {
                let app = c.latest?.app ?? "Notes"
                let r = ImageRenderer(content: FakeWindow(app: app, title: c.latest?.title ?? "Calc homework").frame(width: 800, height: 500))
                r.scale = 2
                if let img = r.cgImage { c.setPreview(img, app: app, text: "Problem set 6 integration by parts u = x dv = e^x dx") }
            }
        }
    }
}

/// A plain drawn window: title bar, a sidebar and lines of a homework note. Synthetic, so nothing real is ever pictured.
struct FakeWindow: View {
    var app: String, title: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 12, height: 12) }
                Spacer(); Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black.opacity(0.7)); Spacer()
            }
            .padding(.horizontal, 14).frame(height: 38).background(Color(white: 0.93))
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(["Calc homework", "Reading notes", "Lab report"], id: \.self) { t in
                        Text(t).font(.system(size: 12, weight: t == "Calc homework" ? .semibold : .regular)).foregroundStyle(.black.opacity(0.75))
                            .padding(.horizontal, 8).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(t == "Calc homework" ? Color.yellow.opacity(0.35) : .clear))
                    }
                    Spacer()
                }
                .padding(12).frame(width: 190).background(Color(white: 0.96))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Problem set 6").font(.system(size: 24, weight: .bold)).foregroundStyle(.black.opacity(0.85))
                    Text("Integration by parts").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black.opacity(0.6))
                    Text("∫ x eˣ dx    u = x,  dv = eˣ dx").font(.system(size: 16, design: .serif)).foregroundStyle(.black.opacity(0.8))
                    Text("= x eˣ − ∫ eˣ dx = x eˣ − eˣ + C").font(.system(size: 16, design: .serif)).foregroundStyle(.black.opacity(0.8))
                    ForEach(0..<5, id: \.self) { i in RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.08)).frame(width: CGFloat(420 - i * 37), height: 10) }
                    Spacer()
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
