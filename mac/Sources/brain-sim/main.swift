import BrainSim
import FocusBrain
import Foundation

// brain-sim --verdicts <json> [--episodes 200] [--hours 3] [--preset Standard|Gentle|Strict] [--shadow] [--seed 1]
//           [--p-off 0.12] [--p-unsure 0.17] [--p-return 0.7] [--churn 30]
func arg(_ name: String) -> String? { let a = CommandLine.arguments; if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }; return nil }
guard let vp = arg("--verdicts") else { print("usage: brain-sim --verdicts eval/results/verdicts_two_judge.json [options]"); exit(2) }
let verdicts = try Sim.loadVerdicts(URL(fileURLWithPath: vp))
let episodes = Int(arg("--episodes") ?? "200")!, hours = Double(arg("--hours") ?? "3")!
let preset = Preset(rawValue: arg("--preset") ?? "Standard")!
let shadow = CommandLine.arguments.contains("--shadow")
let seed = UInt64(arg("--seed") ?? "1")!
var beh = Behaviour()
if let v = arg("--p-off").flatMap(Double.init) { beh.mix["off_task"] = v }
if let v = arg("--p-unsure").flatMap(Double.init) { beh.mix["unsure"] = v }
beh.mix["on_task"] = 1 - (beh.mix["off_task"]! + beh.mix["unsure"]! + beh.mix["sensitive"]!)
if let v = arg("--p-return").flatMap(Double.init) { beh.pReturnAfterNudge = v }
beh.neutralDefaults = CommandLine.arguments.contains("--neutral-defaults")
if let v = arg("--churn").flatMap(Double.init) { beh.contentChurn = v }

var results: [EpisodeResult] = []
for e in 0..<episodes { results.append(Sim.episode(verdicts: verdicts, preset: preset, shadow: shadow, hours: hours, seed: seed &+ UInt64(e), behaviour: beh)) }

let n = results.count
let nudges = results.flatMap { $0.nudges }, marks = results.flatMap { $0.shadowMarks }
let falseN = nudges.filter { $0.gold != "off_task" && !$0.late }.count, lateN = nudges.filter { $0.gold != "off_task" && $0.late }.count, falseM = marks.filter { $0.gold != "off_task" }.count
let withFalse = results.filter { $0.falseNudges > 0 || $0.shadowMarks.contains { $0.gold != "off_task" } }.count
let (lo, hi) = Sim.wilson(withFalse, n)
let dist = results.flatMap { $0.distractions }.filter { $0.dwell >= 120 }
let caught = dist.filter { $0.firstNudgeDelay != nil }
let delays = caught.compactMap { $0.firstNudgeDelay }.sorted()
func pct(_ x: Double) -> String { String(format: "%.0f%%", 100 * x) }
let totalH = Double(n) * hours
print("\(beh.neutralDefaults ? "[neutral defaults on] " : "")preset \(preset.rawValue)\(shadow ? " (shadow: would-be nudges)" : ""), \(n) episodes x \(hours) h, mix on/unsure/off = \(pct(beh.mix["on_task"]!))/\(pct(beh.mix["unsure"]!))/\(pct(beh.mix["off_task"]!)), P(return after nudge) \(pct(beh.pReturnAfterNudge))")
print(String(format: "model calls per hour: %.1f (two framings per judgment in the Mac pipeline: up to 2 x)", Double(results.reduce(0) { $0 + $1.requests }) / totalH))
let count = shadow ? marks.count : nudges.count, falseCount = shadow ? falseM : falseN
print(String(format: "nudges per 3 h: %.2f total, %.2f false (gold was not off task), %.2f late (arrived within 6 s of the user already leaving the distraction)", Double(count) / totalH * 3, Double(falseCount) / totalH * 3, Double(lateN) / totalH * 3))
print("sessions with at least one false nudge: \(withFalse) of \(n) = \(pct(Double(withFalse) / Double(n))) (95% CI \(pct(lo)) to \(pct(hi)))")
print("distractions of 2 min or more: \(dist.count); nudged while still there: \(caught.count) = \(pct(Double(caught.count) / Double(max(1, dist.count))))")
if !delays.isEmpty { print(String(format: "time from start of distraction to first nudge: median %.0f s, 90th percentile %.0f s", delays[delays.count / 2], delays[Int(0.9 * Double(delays.count - 1))])) }
let falseWins = Dictionary(grouping: (shadow ? marks.map { ($0.gold, "") } : nudges.filter { !$0.late }.map { ($0.gold, $0.windowKey) }).filter { $0.0 != "off_task" }, by: { $0.1 }).mapValues { $0.count }.sorted { $0.value > $1.value }
if !shadow && !falseWins.isEmpty { print("windows behind the false nudges: " + falseWins.prefix(5).map { "\($0.key) x\($0.value)" }.joined(separator: ", ")) }
