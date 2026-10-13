//! The wire format: events in and effects out as JSON, the shape of the golden traces (docs/BRAIN-SPEC.md 9.1).
//! The C ABI in ffi.rs and the trace runner both go through this, so the traces test the real boundary format.
use crate::json::J;
use crate::*;

fn s(x: &str) -> J { J::Str(x.into()) }

pub fn label(v: &str) -> Label { match v { "on_task" => Label::OnTask, "unsure" => Label::Unsure, "off_task" => Label::OffTask, o => panic!("label {o}") } }

pub fn decode_event(e: &J) -> Event {
    if e.str() == Some("Tick") { return Event::Tick; }
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
            c.check_scale = g("checkScale").and_then(J::num).unwrap_or(1.0);
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


/// An effect as (type, fields), optional fields omitted. The same shape the golden traces use.
pub fn encode_effect(e: &Effect) -> (String, Vec<(String, J)>) {
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


/// An effect as one JSON object, {"Type": {fields}}.
pub fn effect_json(e: &Effect) -> J {
    let (name, fields) = encode_effect(e);
    J::Obj(vec![(name, J::Obj(fields))])
}
