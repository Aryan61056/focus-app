import Foundation
import FocusBrain

/// Runs a golden trace (core/traces/*.json, format in docs/BRAIN-SPEC.md 9.1) through the Swift brain.
public struct TraceResult {
    public var name: String
    public var failures: [String]
    public var stepsChecked: Int
}

public enum TraceRunner {
    typealias Dict = [String: Any]

    struct Item { var t: Double; var order: Int; var index: Int; var event: Event; var expected: [Dict]; var label: String; var raw: Any = "Tick" }

    /// One canonical line per event, for differential testing against other implementations: index, time, then each effect with sorted
    /// fields and numbers printed to 6 decimals. Expected effects in the file are ignored.
    public static func dump(file: URL) throws -> [String] {
        let items = try buildItems(file: file).items
        var brain = Brain()
        return items.map { it in
            let fx = brain.step(it.t, it.event).map(encode).map(canonical)
            return "\(it.index) \(String(format: "%.3f", it.t)) \(fx.joined(separator: ";"))"
        }
    }

    static func canonical(_ e: (String, Dict)) -> String {
        let f = e.1.keys.sorted().map { k -> String in
            let v = e.1[k]!
            if isBool(v) { return "\(k)=\((v as! NSNumber).boolValue)" }
            if let n = v as? NSNumber { return "\(k)=\(String(format: "%.6f", n.doubleValue))" }
            return "\(k)=\(v)"
        }.joined(separator: ",")
        return "\(e.0){\(f)}"
    }

    /// Runs every event of a trace through the Swift brain and through another implementation reached by `other` (the Rust brain over its
    /// C ABI), comparing the effects. `other` gets the time and the event as JSON and returns the effects as a JSON array, or nil on failure.
    public static func crossCheck(file: URL, other: (Double, String) -> String?) throws -> (events: Int, mismatches: [String]) {
        let items = try buildItems(file: file).items
        var brain = Brain()
        var bad: [String] = []
        for it in items {
            let mine = brain.step(it.t, it.event).map(encode).map(canonical).joined(separator: ";")
            let json: String
            if let d = it.raw as? Dict, let data = try? JSONSerialization.data(withJSONObject: d), let str = String(data: data, encoding: .utf8) { json = str } else { json = "\"Tick\"" }
            guard let out = other(it.t, json), let arr = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [Dict] else { bad.append("\(it.label): other implementation failed"); continue }
            let theirs = arr.map { e -> String in let (k, v) = e.first!; return canonical((k, (v as? Dict) ?? [:])) }.joined(separator: ";")
            if mine != theirs { bad.append("\(it.label)\n    swift: \(mine)\n    other: \(theirs)") }
        }
        return (items.count, bad)
    }

    public static func run(file: URL) throws -> TraceResult {
        let (items, ignore, name) = try buildItems(file: file)
        var brain = Brain()
        var failures: [String] = []
        for it in items {
            let actual = brain.step(it.t, it.event).map(encode).filter { !ignore.contains($0.0) }
            let expected = it.expected.map(normalizeExpected).filter { !ignore.contains($0.0) }
            if !same(actual, expected) {
                failures.append("\(it.label)\n    expected: \(expected.map(show))\n    actual:   \(actual.map(show))")
            }
        }
        return TraceResult(name: name, failures: failures, stepsChecked: items.count)
    }

    static func buildItems(file: URL) throws -> (items: [Item], ignore: Set<String>, name: String) {
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! Dict
        let name = obj["trace"] as! String
        let ignore = Set(obj["ignore"] as? [String] ?? [])
        var steps = obj["steps"] as! [Dict]
        if let pre = obj["prelude"] as? Dict { steps = prelude(pre) + steps }

        var items: [Item] = []
        var tickExpect: [Double: [Dict]] = [:]
        var index = 0
        for s in steps {
            let t = num(s["t"])
            let fx = (s["fx"] as? [Dict]) ?? []
            if let str = s["ev"] as? String, str == "Tick" { tickExpect[t] = fx; continue }
            let ev = s["ev"] as! Dict
            items.append(Item(t: t, order: 0, index: index, event: try decode(ev), expected: fx, label: "t=\(fmt(t)) \(ev.keys.first ?? "")", raw: ev)); index += 1
            if let rep = s["repeat"] as? Dict {
                let every = num(rep["every"]), until = num(rep["until"])
                var k = 1.0
                while t + k * every <= until {
                    var copy = ev
                    if var j = (copy["Judgment"] as? Dict) { j["observedAt"] = num(j["observedAt"]) + k * every; copy["Judgment"] = j }
                    items.append(Item(t: t + k * every, order: 0, index: index, event: try decode(copy), expected: [], label: "t=\(fmt(t + k * every)) repeat of \(ev.keys.first ?? "")", raw: copy)); index += 1
                    k += 1
                }
            }
        }
        if let tk = obj["ticks"] as? Dict {
            var s = num(tk["from"])
            while s <= num(tk["until"]) {
                items.append(Item(t: s, order: 1, index: index, event: .tick, expected: tickExpect[s] ?? [], label: "t=\(fmt(s)) Tick")); index += 1
                s += 1
            }
        }
        items.sort { ($0.t, $0.order, $0.index) < ($1.t, $1.order, $1.index) }

        return (items, ignore, name)
    }

    // MARK: input
    static func prelude(_ pre: Dict) -> [Dict] {
        let dur = pre["durationSeconds"] != nil ? num(pre["durationSeconds"]) : 0
        return [
            ["t": 0.0, "ev": ["SessionStart": pre], "fx": [["Beacon": ["state": "resting"]], ["Clock": ["seconds": dur, "running": true]]]],
            ["t": 0.0, "ev": ["WindowChange": ["windowKey": "w:editor"]], "fx": []],
            ["t": 3.5, "ev": ["Judgment": ["observedAt": 0.0, "windowKey": "w:editor", "contentKey": "c:e1", "label": "on_task"]], "fx": []],
        ]
    }

    static func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
    static func fmt(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

    static func decode(_ e: Dict) throws -> Event {
        guard let (k, v) = e.first else { throw NSError(domain: "trace", code: 1) }
        let p = (v as? Dict) ?? [:]
        switch k {
        case "SessionStart":
            var c = SessionConfig()
            c.sessionId = p["sessionId"] as? String ?? "s"; c.taskId = p["taskId"] as? String ?? "task"
            c.mode = Mode(rawValue: p["mode"] as? String ?? "Open")!
            if p["durationSeconds"] != nil { c.durationSeconds = num(p["durationSeconds"]) }
            c.preset = Preset(rawValue: p["preset"] as? String ?? "Standard")!
            c.shadow = (p["shadow"] as? NSNumber)?.boolValue ?? false
            if let r = p["reentryPrompt"] as? NSNumber { c.reentryPrompt = r.boolValue }
            c.sound = (p["sound"] as? NSNumber)?.boolValue ?? false
            c.checkScale = (p["checkScale"] as? NSNumber)?.doubleValue ?? 1
            return .sessionStart(c)
        case "SessionEnd": return .sessionEnd
        case "Judgment":
            var j = JudgmentInput(requestId: (p["requestId"] as? NSNumber)?.intValue, observedAt: num(p["observedAt"]),
                                  windowKey: p["windowKey"] as! String, contentKey: p["contentKey"] as? String ?? "",
                                  label: JudgmentLabel(rawValue: p["label"] as! String)!)
            j.strong = (p["strong"] as? NSNumber)?.boolValue ?? false
            j.source = JudgmentSource(rawValue: p["source"] as? String ?? "model")!
            j.flag = JudgmentFlag(rawValue: p["flag"] as? String ?? "none")!
            return .judgment(j)
        case "WindowChange":
            return .windowChange(WindowChangeInput(windowKey: p["windowKey"] as! String, siteKey: p["siteKey"] as? String,
                                                   ruleLabel: (p["ruleLabel"] as? String).flatMap { JudgmentLabel(rawValue: $0) }))
        case "UserAction": return .userAction(UserAction(rawValue: p["action"] as! String)!, minutes: (p["minutes"] as? NSNumber)?.intValue)
        case "Idle": return .idle
        case "Active": return .active
        case "Sleep": return .sleep
        case "Wake": return .wake
        case "MeetingStart": return .meetingStart
        case "MeetingEnd": return .meetingEnd
        case "SensitiveEntered": return .sensitiveEntered
        case "SensitiveLeft": return .sensitiveLeft
        case "PowerChange": return .powerChange(constrained: (p["constrained"] as? NSNumber)?.boolValue ?? false, critical: (p["critical"] as? NSNumber)?.boolValue ?? false)
        default: throw NSError(domain: "trace", code: 2, userInfo: [NSLocalizedDescriptionKey: "unknown event \(k)"])
        }
    }

    // MARK: effects as (type, fields), nil fields omitted
    static func encode(_ e: Effect) -> (String, Dict) {
        switch e {
        case .withdraw(let w): return ("Withdraw", ["what": w])
        case .beacon(let s, let r): var d: Dict = ["state": s]; if let r = r { d["reason"] = r }; return ("Beacon", d)
        case .veil(let f, let t, let s): return ("Veil", ["from": f, "to": t, "seconds": s])
        case .offTopicTimer(let s, let r, let v): return ("OffTopicTimer", ["seconds": s, "running": r, "visible": v])
        case .clock(let s, let r): return ("Clock", ["seconds": s, "running": r])
        case .interrupt(let k, let sv, let b, let w): return ("Interrupt", ["kind": k, "severity": sv, "block": b, "windowKey": w])
        case .reentryPrompt(let b): return ("ReentryPrompt", ["block": b])
        case .wrapUp(let r): return ("WrapUp", ["remaining": r])
        case .askResume(let r): return ("AskResume", ["reason": r])
        case .shadowMark(let b, let k, let w): return ("ShadowMark", ["block": b, "kind": k, "windowKey": w])
        case .learnRule(let s, let k, let kt, let key): return ("LearnRule", ["scope": s, "kind": k, "keyType": kt, "key": key])
        case .bringBack(let w): var d: Dict = [:]; if let w = w { d["windowKey"] = w }; return ("BringBack", d)
        case .requestJudgment(let id, let r, let u, let w, let av): return ("RequestJudgment", ["id": id, "reason": r, "urgency": u, "windowKey": w, "allowVision": av])
        case .cue: return ("Cue", ["sound": "soft"])
        case .summary(let a, let o, let u, let d, let i, let r): return ("Summary", ["activeSeconds": a, "offTopicSeconds": o, "unsureSeconds": u, "drifts": d, "interrupts": i, "refusals": r])
        }
    }

    static func normalizeExpected(_ e: Dict) -> (String, Dict) {
        let (k, v) = e.first!
        var d = (v as? Dict) ?? [:]
        d = d.filter { !($0.value is NSNull) }
        if k == "RequestJudgment" && d["allowVision"] == nil { d["allowVision"] = true }
        return (k, d)
    }

    // MARK: comparison (numbers within 1e-6, spec 1)
    static func isBool(_ v: Any) -> Bool { (v as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false }

    static func equal(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? String, let y = b as? String { return x == y }
        if isBool(a) || isBool(b) { return isBool(a) && isBool(b) && (a as! NSNumber).boolValue == (b as! NSNumber).boolValue }
        if let x = a as? NSNumber, let y = b as? NSNumber { return abs(x.doubleValue - y.doubleValue) <= 1e-6 }
        return false
    }

    static func same(_ a: [(String, Dict)], _ b: [(String, Dict)]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) {
            guard x.0 == y.0, x.1.count == y.1.count else { return false }
            for (k, v) in x.1 { guard let w = y.1[k], equal(v, w) else { return false } }
        }
        return true
    }

    static func show(_ e: (String, Dict)) -> String {
        let f = e.1.keys.sorted().map { "\($0): \(e.1[$0]!)" }.joined(separator: ", ")
        return "\(e.0){\(f)}"
    }
}
