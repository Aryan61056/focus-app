import FocusJudge
import Foundation

// focus-judge: run the detection pipeline from the command line.
//   focus-judge --dump-prompts <scenarios dir>            print "id<TAB>v1|v2<TAB>json-string" lines for parity checks
//   focus-judge --run <scenarios dir> [--out file.json] [--no-rules] [--stub]
// --stub runs the rules and prompts with a judge that always answers unsure, so it works without Apple Intelligence.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

struct StubJudge: Judge {
    func reasonFirst(prompt: String) async -> Verdict { Verdict(label: .unsure, reason: "stub") }
    func relation(prompt: String) async -> Verdict { Verdict(label: .unsure, reason: "stub") }
}

func jsonString(_ s: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])
    var out = String(data: data, encoding: .utf8)!
    out.removeFirst(); out.removeLast()
    return out
}

let args = Array(CommandLine.arguments.dropFirst())
guard let mode = args.first, args.count >= 2 else { fail("usage: focus-judge --dump-prompts|--run <scenarios dir> [--out file] [--no-rules] [--stub]") }
let dir = URL(fileURLWithPath: args[1])
let scenarios: [Scenario]
do { scenarios = try Scenario.loadAll(directory: dir) } catch { fail("cannot load scenarios: \(error)") }

switch mode {
case "--dump-prompts":
    for s in scenarios {
        print("\(s.id)\t\(jsonString(Prompts.prompt(for: s.moment)))")
    }
case "--run":
    let useRules = !args.contains("--no-rules")
    var outPath: String?
    if let i = args.firstIndex(of: "--out"), i + 1 < args.count { outPath = args[i + 1] }
    var judge: Judge = StubJudge()
    if !args.contains("--stub") {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .unavailable(let why) = AppleJudge.availability { fail("Apple on-device model unavailable: \(why)") }
            judge = AppleJudge()
        } else { fail("needs macOS 26 or later") }
        #else
        fail("FoundationModels is not available in this build")
        #endif
    }
    var rows: [[String: Any]] = []
    for (i, s) in scenarios.enumerated() {
        let j = await Pipeline.judge(s.moment, with: judge, useRules: useRules)
        FileHandle.standardError.write(Data("[\(i + 1)/\(scenarios.count)] \(s.id) gold=\(s.label.rawValue) pred=\(j.label.rawValue)\n".utf8))
        rows.append([
            "id": s.id, "category": s.category, "difficulty": s.difficulty, "gold": s.label.rawValue, "tags": s.tags,
            "title": s.windowTitle, "pred": j.label.rawValue, "confidence": NSNull(), "stage": j.stage.rawValue,
            "reason": j.reason, "latency_ms": j.latencyMs, "error": j.error as Any? ?? NSNull(),
            "first": j.firstLabel?.rawValue ?? NSNull(), "second": j.secondLabel?.rawValue ?? NSNull(),
        ])
    }
    let meta: [String: Any] = ["backend": args.contains("--stub") ? "swift-stub" : "swift-apple-two-judge", "rules": useRules]
    let data = try JSONSerialization.data(withJSONObject: ["meta": meta, "results": rows], options: [.prettyPrinted, .sortedKeys])
    if let p = outPath { try data.write(to: URL(fileURLWithPath: p)); print("saved \(p)") } else { print(String(data: data, encoding: .utf8)!) }
default:
    fail("unknown mode \(mode)")
}
