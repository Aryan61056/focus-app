//! Runs the golden traces (core/traces/*.json, format in docs/BRAIN-SPEC.md 9.1) through the Rust brain.
//! Usage: trace <traces dir>. Includes a tiny JSON reader so the crate needs no dependencies.
use focus_brain::json::{self, J};
use focus_brain::wire::{decode_event as decode, encode_effect as encode};
use focus_brain::*;
use std::collections::HashMap;

fn obj(v: Vec<(&str, J)>) -> J { J::Obj(v.into_iter().map(|(k, x)| (k.to_string(), x)).collect()) }
fn s(x: &str) -> J { J::Str(x.into()) }

fn normalize_expected(e: &J) -> (String, Vec<(String, J)>) {
    let (k, v) = e.first().unwrap();
    let mut d: Vec<(String, J)> = match v { J::Obj(o) => o.iter().filter(|(_, x)| *x != J::Null).cloned().collect(), _ => vec![] };
    if k == "RequestJudgment" && !d.iter().any(|(n, _)| n == "allowVision") { d.push(("allowVision".into(), J::Bool(true))); }
    (k.clone(), d)
}

fn eq(a: &J, b: &J) -> bool {
    match (a, b) { (J::Str(x), J::Str(y)) => x == y, (J::Bool(x), J::Bool(y)) => x == y, (J::Num(x), J::Num(y)) => (x - y).abs() <= 1e-6, _ => false }
}

fn same(a: &[(String, Vec<(String, J)>)], b: &[(String, Vec<(String, J)>)]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(x, y)| x.0 == y.0 && x.1.len() == y.1.len() && x.1.iter().all(|(k, v)| y.1.iter().find(|(n, _)| n == k).map_or(false, |(_, w)| eq(v, w))))
}

fn show(e: &(String, Vec<(String, J)>)) -> String {
    let mut f: Vec<String> = e.1.iter().map(|(k, v)| format!("{k}: {}", match v { J::Str(x) => x.clone(), J::Num(n) => n.to_string(), J::Bool(b) => b.to_string(), o => format!("{o:?}") })).collect();
    f.sort(); format!("{}{{{}}}", e.0, f.join(", "))
}

struct Item { t: f64, order: i32, index: usize, event: Event, expected: Vec<J>, label: String }

fn prelude(pre: &J) -> Vec<J> {
    let dur = pre.get("durationSeconds").and_then(J::num).unwrap_or(0.0);
    vec![
        obj(vec![("t", J::Num(0.0)), ("ev", obj(vec![("SessionStart", pre.clone())])), ("fx", J::Arr(vec![obj(vec![("Beacon", obj(vec![("state", s("resting"))]))]), obj(vec![("Clock", obj(vec![("seconds", J::Num(dur)), ("running", J::Bool(true))]))])]))]),
        obj(vec![("t", J::Num(0.0)), ("ev", obj(vec![("WindowChange", obj(vec![("windowKey", s("w:editor"))]))])), ("fx", J::Arr(vec![]))]),
        obj(vec![("t", J::Num(3.5)), ("ev", obj(vec![("Judgment", obj(vec![("observedAt", J::Num(0.0)), ("windowKey", s("w:editor")), ("contentKey", s("c:e1")), ("label", s("on_task"))]))])), ("fx", J::Arr(vec![]))]),
    ]
}

/// One canonical line per event, same format as `brain-trace --dump`: index, time, effects with sorted fields, numbers to 6 decimals.
fn dump(path: &std::path::Path) {
    let (items, _, _) = build(path);
    let mut brain = Brain::new();
    for it in &items {
        let fx: Vec<String> = brain.step(it.t, it.event.clone()).iter().map(|e| {
            let (name, mut fields) = encode(e);
            fields.sort_by(|a, b| a.0.cmp(&b.0));
            let f: Vec<String> = fields.iter().map(|(k, v)| format!("{k}={}", match v { J::Str(x) => x.clone(), J::Num(n) => format!("{:.6}", n), J::Bool(b) => b.to_string(), _ => String::new() })).collect();
            format!("{name}{{{}}}", f.join(","))
        }).collect();
        println!("{} {:.3} {}", it.index, it.t, fx.join(";"));
    }
}

fn run(path: &std::path::Path) -> (String, Vec<String>, usize) {
    let (items, ignore, name) = build(path);
    let mut brain = Brain::new();
    let mut failures = vec![];
    for it in &items {
        let actual: Vec<_> = brain.step(it.t, it.event.clone()).iter().map(encode).filter(|e| !ignore.contains(&e.0)).collect();
        let expected: Vec<_> = it.expected.iter().map(normalize_expected).filter(|e| !ignore.contains(&e.0)).collect();
        if !same(&actual, &expected) {
            failures.push(format!("{}\n    expected: {:?}\n    actual:   {:?}", it.label, expected.iter().map(show).collect::<Vec<_>>(), actual.iter().map(show).collect::<Vec<_>>()));
        }
    }
    (name, failures, items.len())
}

fn build(path: &std::path::Path) -> (Vec<Item>, Vec<String>, String) {
    let text = std::fs::read_to_string(path).unwrap();
    let root = json::parse(&text);
    let name = root.get("trace").and_then(J::str).unwrap().to_string();
    let ignore: Vec<String> = root.get("ignore").and_then(J::arr).map(|a| a.iter().filter_map(|x| x.str().map(String::from)).collect()).unwrap_or_default();
    let mut steps: Vec<J> = root.get("steps").and_then(J::arr).unwrap().clone();
    if let Some(pre) = root.get("prelude") { let mut p = prelude(pre); p.extend(steps); steps = p; }

    let mut items: Vec<Item> = vec![];
    let mut tick_expect: HashMap<u64, Vec<J>> = HashMap::new();
    let mut index = 0;
    for st in &steps {
        let t = st.get("t").and_then(J::num).unwrap_or(0.0);
        let fx: Vec<J> = st.get("fx").and_then(J::arr).cloned().unwrap_or_default();
        let ev = st.get("ev").unwrap();
        if ev.str() == Some("Tick") { tick_expect.insert(t.to_bits(), fx); continue; }
        let en = ev.first().unwrap().0.clone();
        items.push(Item { t, order: 0, index, event: decode(ev), expected: fx, label: format!("t={} {}", t, en) }); index += 1;
        if let Some(rep) = st.get("repeat") {
            let every = rep.get("every").and_then(J::num).unwrap(); let until = rep.get("until").and_then(J::num).unwrap();
            let mut k = 1.0;
            while t + k * every <= until {
                let mut copy = ev.clone();
                if let J::Obj(o) = &mut copy {
                    for (_, v) in o.iter_mut() { if let J::Obj(inner) = v { for (n, x) in inner.iter_mut() { if n == "observedAt" { if let J::Num(c) = x { *c += k * every; } } } } }
                }
                items.push(Item { t: t + k * every, order: 0, index, event: decode(&copy), expected: vec![], label: format!("t={} repeat of {}", t + k * every, en) }); index += 1;
                k += 1.0;
            }
        }
    }
    if let Some(tk) = root.get("ticks") {
        let mut sec = tk.get("from").and_then(J::num).unwrap(); let until = tk.get("until").and_then(J::num).unwrap();
        while sec <= until {
            items.push(Item { t: sec, order: 1, index, event: Event::Tick, expected: tick_expect.get(&sec.to_bits()).cloned().unwrap_or_default(), label: format!("t={} Tick", sec) }); index += 1;
            sec += 1.0;
        }
    }
    items.sort_by(|a, b| a.t.partial_cmp(&b.t).unwrap().then(a.order.cmp(&b.order)).then(a.index.cmp(&b.index)));

    (items, ignore, name)
}

fn main() {
    let a1 = std::env::args().nth(1).expect("usage: trace <traces dir> | trace --dump <trace.json>");
    if a1 == "--dump" { dump(std::path::Path::new(&std::env::args().nth(2).expect("trace file"))); return; }
    let dir = a1;
    let mut files: Vec<_> = std::fs::read_dir(&dir).unwrap().filter_map(|e| e.ok()).map(|e| e.path()).filter(|p| p.extension().map_or(false, |x| x == "json")).collect();
    files.sort();
    let mut bad = 0;
    for f in &files {
        let (name, failures, n) = run(f);
        if failures.is_empty() { println!("PASS {name} ({n} events)"); } else { bad += 1; println!("FAIL {name}"); for x in failures.iter().take(3) { println!("  {x}"); } }
    }
    if bad == 0 { println!("all {} traces pass", files.len()); } else { println!("{bad} of {} traces fail", files.len()); std::process::exit(1); }
}
