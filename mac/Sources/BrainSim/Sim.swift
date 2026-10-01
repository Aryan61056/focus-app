import Foundation
import FocusBrain

/// Episode simulator: replays the recorded per-moment verdicts (eval/results/verdicts_two_judge.json) through the brain
/// to estimate things per-moment metrics cannot: nudges and false nudges per session, time to nudge, model calls per hour.
/// The verdicts are real (Apple's model on synthetic scenarios). The user behavior is an ASSUMPTION, set by Behaviour.
public struct Verdict: Sendable {
    public var id: String, gold: String, pred: String, stage: String
    public var refused: Bool, sensitive: Bool
    public var app: String, title: String
}

public struct Behaviour: Sendable {
    public var mix: [String: Double] = ["on_task": 0.70, "unsure": 0.17, "off_task": 0.12, "sensitive": 0.01]
    public var dwell: [String: ClosedRange<Double>] = ["on_task": 20...400, "unsure": 10...180, "off_task": 15...600, "sensitive": 10...60]
    public var contentChurn = 30.0        // seconds between content changes inside one window (feeds, scrolling)
    public var judgeLatency = 3.5
    public var pReturnAfterNudge = 0.7    // otherwise the user ignores the nudge and keeps going
    public var returnDelay: ClosedRange<Double> = 3...20
    /// Default allow-list: personal messaging apps and start pages are never judged (verdict forced to unsure by a rule).
    public var neutralDefaults = false
    public init() {}
}

public struct EpisodeResult: Sendable {
    public var seconds = 0.0
    public var requests = 0
    public var nudges: [(t: Double, gold: String, windowKey: String, late: Bool)] = []
    public var shadowMarks: [(t: Double, gold: String)] = []
    public var distractions: [(start: Double, dwell: Double, firstNudgeDelay: Double?)] = []
    public var falseNudges: Int { nudges.filter { $0.gold != "off_task" && !$0.late }.count }
    public var lateNudges: Int { nudges.filter { $0.gold != "off_task" && $0.late }.count }
}

struct LCG { var s: UInt64
    mutating func u() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    mutating func pick<T>(_ a: [T]) -> T { a[Int(u() * Double(a.count)) % a.count] }
    mutating func logUniform(_ r: ClosedRange<Double>) -> Double { exp(log(r.lowerBound) + u() * (log(r.upperBound) - log(r.lowerBound))).rounded() }
}

public enum Sim {
    public static func loadVerdicts(_ url: URL) throws -> [Verdict] {
        let arr = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        return arr.map { Verdict(id: $0["id"] as! String, gold: $0["gold"] as! String, pred: $0["pred"] as! String, stage: $0["stage"] as! String,
                                 refused: $0["refused"] as? Bool ?? false, sensitive: $0["sensitive"] as? Bool ?? false,
                                 app: $0["app"] as? String ?? "", title: $0["title"] as? String ?? "") }
    }

    struct Segment { var v: Verdict; var start: Double; var end: Double }
    struct Pending { var due: Double; var observedAt: Double; var windowKey: String; var contentKey: String }

    public static func episode(verdicts: [Verdict], preset: Preset, shadow: Bool, hours: Double, seed: UInt64, behaviour b: Behaviour = Behaviour()) -> EpisodeResult {
        var rng = LCG(s: seed &* 2654435761 &+ 12345)
        let neutralApps: Set<String> = ["Messages", "WhatsApp", "Signal", "Telegram"]
        let neutralTitles = ["Start Page", "New Tab", "about:blank"]
        let verdicts: [Verdict] = !b.neutralDefaults ? verdicts : verdicts.map { v in
            var v = v
            if neutralApps.contains(v.app) || neutralTitles.contains(where: { v.title.contains($0) }) { v.pred = "unsure"; v.stage = "model" }
            return v
        }
        let byGold: [String: [Verdict]] = [
            "on_task": verdicts.filter { $0.gold == "on_task" && !$0.sensitive },
            "unsure": verdicts.filter { $0.gold == "unsure" && !$0.sensitive },
            "off_task": verdicts.filter { $0.gold == "off_task" && !$0.sensitive },
            "sensitive": verdicts.filter { $0.sensitive },
        ]
        let byId = Dictionary(uniqueKeysWithValues: verdicts.map { ($0.id, $0) })
        let total = hours * 3600

        func nextSegment(from t: Double, forceOn: Bool = false) -> Segment {
            var kind = "on_task"
            if !forceOn {
                var x = rng.u(), acc = 0.0
                for k in ["on_task", "unsure", "off_task", "sensitive"] { acc += b.mix[k] ?? 0; if x < acc { kind = k; break }; x -= 0 }
            }
            let v = rng.pick(byGold[kind]!)
            let dwell = rng.logUniform(b.dwell[kind]!)
            return Segment(v: v, start: t, end: t + dwell)
        }

        var brain = Brain()
        var res = EpisodeResult()
        var cfg = SessionConfig(); cfg.preset = preset; cfg.shadow = shadow
        _ = brain.step(0, .sessionStart(cfg))

        var seg = nextSegment(from: 0, forceOn: true)
        var prevGold = "on_task"
        var pending: [Pending] = []
        var returnAt: Double?
        var sensitiveUp = false
        var segCounter = 0
        var lastGold = "on_task"
        var distraction: (start: Double, dwell: Double, nudged: Double?)?

        func enter(_ s: Segment, _ t: Double) {
            segCounter += 1
            prevGold = lastGold; lastGold = s.v.gold
            if let d = distraction { res.distractions.append((d.start, d.dwell, d.nudged.map { $0 - d.start })); distraction = nil }
            if s.v.gold == "off_task" { distraction = (t, s.end - s.start, nil) }
            if s.v.sensitive {
                sensitiveUp = true
                _ = brain.step(t, .sensitiveEntered)
            } else {
                var rule: JudgmentLabel?
                if s.v.stage == "rule" { rule = s.v.pred == "on_task" ? .onTask : (s.v.pred == "off_task" ? .offTask : nil) }
                handle(brain.step(t, .windowChange(WindowChangeInput(windowKey: s.v.id, siteKey: s.v.id, ruleLabel: rule))), t)
            }
        }
        func handle(_ fx: [Effect], _ t: Double) {
            for e in fx {
                switch e {
                case .requestJudgment(_, _, _, let wk, _):
                    res.requests += 1
                    let content = "\(wk)#\(Int((t - seg.start) / b.contentChurn))"
                    pending.append(Pending(due: t + b.judgeLatency, observedAt: t, windowKey: wk, contentKey: content))
                case .interrupt:
                    res.nudges.append((t, seg.v.gold, seg.v.id, t - seg.start <= 6 && prevGold == "off_task"))
                    if var d = distraction, d.nudged == nil, seg.v.gold == "off_task" { d.nudged = t; distraction = d }
                    if rng.u() < b.pReturnAfterNudge { returnAt = t + b.returnDelay.lowerBound + rng.u() * (b.returnDelay.upperBound - b.returnDelay.lowerBound) }
                case .shadowMark:
                    res.shadowMarks.append((t, seg.v.gold))
                    if var d = distraction, d.nudged == nil, seg.v.gold == "off_task" { d.nudged = t; distraction = d }
                default: break
                }
            }
        }

        enter(seg, 0)
        var t = 0.0
        while t < total {
            t += 0.5
            if t == t.rounded(.down) {
                if let r = returnAt, t >= r {
                    returnAt = nil
                    if sensitiveUp { _ = brain.step(t, .sensitiveLeft); sensitiveUp = false }
                    seg = nextSegment(from: t, forceOn: true); enter(seg, t)
                } else if t >= seg.end {
                    if sensitiveUp { handle(brain.step(t, .sensitiveLeft), t); sensitiveUp = false }
                    seg = nextSegment(from: t); enter(seg, t)
                }
            }
            // deliver judgments whose time has come
            for p in pending.filter({ $0.due <= t }) {
                if let v = byId[p.windowKey], p.windowKey == seg.v.id, !v.sensitive {
                    var j = JudgmentInput(observedAt: p.observedAt, windowKey: p.windowKey, contentKey: p.contentKey,
                                          label: JudgmentLabel(rawValue: v.pred)!)
                    j.strong = v.pred == "off_task"
                    if v.refused { j.flag = .refusal }
                    handle(brain.step(t, .judgment(j)), t)
                }
            }
            pending.removeAll { $0.due <= t }
            if t == t.rounded(.down) { handle(brain.step(t, .tick), t) }
        }
        if let d = distraction { res.distractions.append((d.start, d.dwell, d.nudged.map { $0 - d.start })) }
        res.seconds = total
        return res
    }

    public static func wilson(_ k: Int, _ n: Int) -> (Double, Double) {
        guard n > 0 else { return (0, 1) }
        let z = 1.96, p = Double(k) / Double(n), d = 1 + z * z / Double(n)
        let c = p + z * z / (2 * Double(n)), m = z * sqrt(p * (1 - p) / Double(n) + z * z / (4 * Double(n * n)))
        return ((c - m) / d, (c + m) / d)
    }
}
