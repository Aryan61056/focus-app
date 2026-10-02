//! Runs the golden traces (core/traces/*.json, format in docs/BRAIN-SPEC.md 9.1) through the Rust brain.
//! Usage: trace <traces dir>. Includes a tiny JSON reader so the crate needs no dependencies.
use focus_brain::*;
use std::collections::HashMap;

#[derive(Clone, Debug, PartialEq)]
enum J { Null, Bool(bool), Num(f64), Str(String), Arr(Vec<J>), Obj(Vec<(String, J)>) }

impl J {
    fn get(&self, k: &str) -> Option<&J> { if let J::Obj(v) = self { v.iter().find(|(n, _)| n == k).map(|(_, x)| x) } else { None } }
    fn str(&self) -> Option<&str> { if let J::Str(s) = self { Some(s) } else { None } }
    fn num(&self) -> Option<f64> { if let J::Num(n) = self { Some(*n) } else { None } }
    fn bool(&self) -> Option<bool> { if let J::Bool(b) = self { Some(*b) } else { None } }
    fn arr(&self) -> Option<&Vec<J>> { if let J::Arr(a) = self { Some(a) } else { None } }
    fn first(&self) -> Option<(&String, &J)> { if let J::Obj(v) = self { v.first().map(|(k, x)| (k, x)) } else { None } }
}

struct P<'a> { b: &'a [u8], i: usize }
impl<'a> P<'a> {
    fn ws(&mut self) { while self.i < self.b.len() && (self.b[self.i] as char).is_whitespace() { self.i += 1; } }
    fn parse(&mut self) -> J {
        self.ws();
        match self.b[self.i] {
            b'{' => { self.i += 1; let mut v = vec![]; loop { self.ws(); if self.b[self.i] == b'}' { self.i += 1; break; }
                      let k = match self.parse() { J::Str(s) => s, _ => panic!("key") }; self.ws(); assert_eq!(self.b[self.i], b':'); self.i += 1;
                      let x = self.parse(); v.push((k, x)); self.ws(); if self.b[self.i] == b',' { self.i += 1; } } J::Obj(v) }
            b'[' => { self.i += 1; let mut v = vec![]; loop { self.ws(); if self.b[self.i] == b']' { self.i += 1; break; }
                      v.push(self.parse()); self.ws(); if self.b[self.i] == b',' { self.i += 1; } } J::Arr(v) }
            b'"' => { self.i += 1; let mut s = String::new(); loop { let c = self.b[self.i]; self.i += 1;
                      match c { b'"' => break, b'\\' => { let e = self.b[self.i]; self.i += 1; match e { b'n' => s.push('\n'), b't' => s.push('\t'), b'r' => s.push('\r'),
                                b'u' => { let h = std::str::from_utf8(&self.b[self.i..self.i + 4]).unwrap(); self.i += 4; s.push(char::from_u32(u32::from_str_radix(h, 16).unwrap()).unwrap_or('?')); }
                                o => s.push(o as char) } }
                                _ => { // copy a full UTF-8 sequence
                                    let start = self.i - 1; let mut end = self.i; while end < self.b.len() && (self.b[end] & 0xC0) == 0x80 { end += 1; }
                                    s.push_str(std::str::from_utf8(&self.b[start..end]).unwrap()); self.i = end; } } } J::Str(s) }
            b't' => { self.i += 4; J::Bool(true) } b'f' => { self.i += 5; J::Bool(false) } b'n' => { self.i += 4; J::Null }
            _ => { let s = self.i; while self.i < self.b.len() && matches!(self.b[self.i], b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9') { self.i += 1; }
                   J::Num(std::str::from_utf8(&self.b[s..self.i]).unwrap().parse().unwrap()) }
        }
    }
}

fn obj(v: Vec<(&str, J)>) -> J { J::Obj(v.into_iter().map(|(k, x)| (k.to_string(), x)).collect()) }
fn s(x: &str) -> J { J::Str(x.into()) }

fn label(v: &str) -> Label { match v { "on_task" => Label::OnTask, "unsure" => Label::Unsure, "off_task" => Label::OffTask, o => panic!("label {o}") } }

fn decode(e: &J) -> Event {
    let (k, p) = e.first().expect("event");
    let g = |n: &str| p.get(n);
    match k.as_str() {
        "SessionStart" => {
            let mut c = SessionConfig::default();
            if let Some(v) = g("sessionId").and_then(J::str) { c.session_id = v.into(); }
            if let Some(v) = g("taskId").and_then(J::str) { c.task_id = v.into(); }
            c.mode = if g("mode").and_then(J::str) == Some("Timed") { Mode::Timed } else { Mode::Open };
            c.duration_seconds = g("durationSeconds").and_then(J::num);
            c.preset = match g("preset").and_then(J::str).unwrap_or("Standard") { "Gentle" => Preset::Gentle, "Strict" => Preset::Strict, _ => Preset::Standard };
            c.shadow = g("shadow").and_then(J::bool).unwrap_or(false);
            c.reentry_prompt = g("reentryPrompt").and_then(J::bool);
            c.sound = g("sound").and_then(J::bool).unwrap_or(false);
            Event::SessionStart(c)
        }
        "SessionEnd" => Event::SessionEnd,
        "Judgment" => Event::Judgment(JudgmentInput {
            request_id: g("requestId").and_then(J::num).map(|n| n as i64), observed_at: g("observedAt").and_then(J::num).unwrap_or(0.0),
            window_key: g("windowKey").and_then(J::str).unwrap().into(), content_key: g("contentKey").and_then(J::str).unwrap_or("").into(),
            label: label(g("label").and_then(J::str).unwrap()), strong: g("strong").and_then(J::bool).unwrap_or(false),
            source: match g("source").and_then(J::str).unwrap_or("model") { "unchanged" => JSource::Unchanged, "rule" => JSource::Rule, _ => JSource::Model },
            flag: match g("flag").and_then(J::str).unwrap_or("none") { "refusal" => Flag::Refusal, "error" => Flag::Error, _ => Flag::None },
        }),
        "WindowChange" => { let wk: String = g("windowKey").and_then(J::str).unwrap().into();
            Event::WindowChange(WindowChangeInput { site_key: g("siteKey").and_then(J::str).map(String::from).unwrap_or_else(|| wk.clone()), window_key: wk,
                                                    rule_label: g("ruleLabel").and_then(J::str).map(label) }) }
        "UserAction" => {
            let a = match g("action").and_then(J::str).unwrap() {
                "pause" => UserAction::Pause, "resume" => UserAction::Resume, "snooze" => UserAction::Snooze, "extend" => UserAction::Extend, "end" => UserAction::End,
                "dismiss" => UserAction::Dismiss, "panic" => UserAction::Panic, "break" => UserAction::BreakTime, "that_was_fine" => UserAction::ThatWasFine,
                "mark_relevant" => UserAction::MarkRelevant, "ignore_window" => UserAction::IgnoreWindow, "mark_off_task" => UserAction::MarkOffTask,
                "back_to_task" => UserAction::BackToTask, "next_step" => UserAction::NextStep, o => panic!("action {o}") };
            Event::UserAction(a, g("minutes").and_then(J::num).map(|n| n as i64))
        }
        "Idle" => Event::Idle, "Active" => Event::Active, "Sleep" => Event::Sleep, "Wake" => Event::Wake,
        "MeetingStart" => Event::MeetingStart, "MeetingEnd" => Event::MeetingEnd,
        "SensitiveEntered" => Event::SensitiveEntered, "SensitiveLeft" => Event::SensitiveLeft,
        "PowerChange" => Event::PowerChange { constrained: g("constrained").and_then(J::bool).unwrap_or(false), critical: g("critical").and_then(J::bool).unwrap_or(false) },
        o => panic!("unknown event {o}"),
    }
}

/// An effect as (type, fields), optional fields omitted, like the Swift runner.
fn encode(e: &Effect) -> (String, Vec<(String, J)>) {
    let f = |v: Vec<(&str, J)>| v.into_iter().map(|(k, x)| (k.to_string(), x)).collect::<Vec<_>>();
    let n = |x: i64| J::Num(x as f64);
    match e {
        Effect::Withdraw { what } => ("Withdraw".into(), f(vec![("what", s(what))])),
        Effect::Beacon { state, reason } => { let mut v = vec![("state", s(state))]; if let Some(r) = reason { v.push(("reason", s(r))); } ("Beacon".into(), f(v)) }
        Effect::Veil { from, to, seconds } => ("Veil".into(), f(vec![("from", n(*from)), ("to", n(*to)), ("seconds", n(*seconds))])),
        Effect::OffTopicTimer { seconds, running, visible } => ("OffTopicTimer".into(), f(vec![("seconds", J::Num(*seconds)), ("running", J::Bool(*running)), ("visible", J::Bool(*visible))])),
        Effect::Clock { seconds, running } => ("Clock".into(), f(vec![("seconds", J::Num(*seconds)), ("running", J::Bool(*running))])),
        Effect::Interrupt { kind, severity, block, window_key } => ("Interrupt".into(), f(vec![("kind", s(kind)), ("severity", n(*severity)), ("block", n(*block)), ("windowKey", s(window_key))])),
        Effect::ReentryPrompt { block } => ("ReentryPrompt".into(), f(vec![("block", n(*block))])),
        Effect::WrapUp { remaining } => ("WrapUp".into(), f(vec![("remaining", J::Num(*remaining))])),
        Effect::AskResume { reason } => ("AskResume".into(), f(vec![("reason", s(reason))])),
        Effect::ShadowMark { block, kind, window_key } => ("ShadowMark".into(), f(vec![("block", n(*block)), ("kind", s(kind)), ("windowKey", s(window_key))])),
        Effect::LearnRule { scope, kind, key_type, key } => ("LearnRule".into(), f(vec![("scope", s(scope)), ("kind", s(kind)), ("keyType", s(key_type)), ("key", s(key))])),
        Effect::BringBack { window_key } => ("BringBack".into(), f(window_key.iter().map(|w| ("windowKey", s(w))).collect())),
        Effect::RequestJudgment { id, reason, urgency, window_key, allow_vision } => ("RequestJudgment".into(), f(vec![("id", n(*id)), ("reason", s(reason)), ("urgency", s(urgency)), ("windowKey", s(window_key)), ("allowVision", J::Bool(*allow_vision))])),
        Effect::Cue => ("Cue".into(), f(vec![("sound", s("soft"))])),
        Effect::Summary { active_seconds, off_topic_seconds, unsure_seconds, drifts, interrupts, refusals } => ("Summary".into(), f(vec![("activeSeconds", J::Num(*active_seconds)), ("offTopicSeconds", J::Num(*off_topic_seconds)), ("unsureSeconds", J::Num(*unsure_seconds)), ("drifts", n(*drifts)), ("interrupts", n(*interrupts)), ("refusals", n(*refusals))])),
    }
}

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
    let root = P { b: text.as_bytes(), i: 0 }.parse();
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
