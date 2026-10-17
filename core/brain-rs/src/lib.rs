//! The focus brain in Rust: a pure state machine, `step(t, event) -> Vec<Effect>`.
//! Port of mac/Sources/FocusBrain (which implements docs/BRAIN-SPEC.md draft 0.1). Spike S5: does a shared Rust core hold up?
//! No dependencies, no I/O, no clock, no randomness: the same events give the same effects everywhere.

pub mod ffi;
pub mod json;
pub mod wire;

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Mode { Timed, Open }
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Preset { Gentle, Standard, Strict }
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Label { OnTask, Unsure, OffTask }
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum JSource { Model, Unchanged, Rule }
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Flag { None, Refusal, Error }

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum UserAction {
    Pause, Resume, Snooze, Extend, End, Dismiss, Panic, BreakTime,
    ThatWasFine, MarkRelevant, IgnoreWindow, MarkOffTask, BackToTask, NextStep,
}

#[derive(Clone, Debug)]
pub struct SessionConfig {
    pub session_id: String, pub task_id: String,
    pub mode: Mode, pub duration_seconds: Option<f64>, pub preset: Preset,
    pub shadow: bool, pub reentry_prompt: Option<bool>, pub sound: bool, pub check_scale: f64,
}
impl Default for SessionConfig {
    fn default() -> Self {
        SessionConfig { session_id: "s".into(), task_id: "task".into(), mode: Mode::Open, duration_seconds: None, preset: Preset::Standard, shadow: false, reentry_prompt: None, sound: false, check_scale: 1.0 }
    }
}

#[derive(Clone, Debug)]
pub struct JudgmentInput {
    pub request_id: Option<i64>, pub observed_at: f64, pub window_key: String, pub content_key: String,
    pub label: Label, pub strong: bool, pub source: JSource, pub flag: Flag,
}

#[derive(Clone, Debug)]
pub struct WindowChangeInput { pub window_key: String, pub site_key: String, pub rule_label: Option<Label> }

#[derive(Clone, Debug)]
pub enum Event {
    SessionStart(SessionConfig), SessionEnd, TaskChanged, Tick, Judgment(JudgmentInput), WindowChange(WindowChangeInput),
    UserAction(UserAction, Option<i64>), Idle, Active, Sleep, Wake, MeetingStart, MeetingEnd,
    SensitiveEntered, SensitiveLeft, PowerChange { constrained: bool, critical: bool },
}

#[derive(Clone, PartialEq, Debug)]
pub enum Effect {
    Withdraw { what: String },
    Beacon { state: String, reason: Option<String> },
    Veil { from: i64, to: i64, seconds: i64 },
    OffTopicTimer { seconds: f64, running: bool, visible: bool },
    Clock { seconds: f64, running: bool },
    Interrupt { kind: String, severity: i64, block: i64, window_key: String },
    ReentryPrompt { block: i64 },
    WrapUp { remaining: f64 },
    AskResume { reason: String },
    ShadowMark { block: i64, kind: String, window_key: String },
    LearnRule { scope: String, kind: String, key_type: String, key: String },
    BringBack { window_key: Option<String> },
    RequestJudgment { id: i64, reason: String, urgency: String, window_key: String, allow_vision: bool },
    Cue,
    Summary { active_seconds: f64, off_topic_seconds: f64, unsure_seconds: f64, drifts: i64, interrupts: i64, refusals: i64 },
}

impl Effect {
    /// Position in the fixed emission order of spec section 5.2.
    fn order(&self) -> i32 {
        match self {
            Effect::Withdraw { .. } => 1, Effect::Beacon { .. } => 2, Effect::Veil { .. } => 3, Effect::OffTopicTimer { .. } => 4,
            Effect::Clock { .. } => 5, Effect::Interrupt { .. } => 6, Effect::ReentryPrompt { .. } => 7, Effect::WrapUp { .. } => 8,
            Effect::AskResume { .. } => 9, Effect::ShadowMark { .. } => 10, Effect::LearnRule { .. } => 11, Effect::BringBack { .. } => 12,
            Effect::RequestJudgment { .. } => 13, Effect::Cue => 14, Effect::Summary { .. } => 15,
        }
    }
}

#[derive(Clone, Copy)]
struct Policy {
    grace: f64, timer_visible_from: f64, veil_drift: i64, veil_cap: i64, confirm_after: f64,
    interrupt_kind: &'static str, repeat_every: Option<f64>, reentry_default: bool,
}
impl Policy {
    fn of(p: Preset) -> Policy {
        match p {
            Preset::Gentle => Policy { grace: 45.0, timer_visible_from: 60.0, veil_drift: 0, veil_cap: 0, confirm_after: 180.0, interrupt_kind: "notice", repeat_every: None, reentry_default: false },
            Preset::Standard => Policy { grace: 25.0, timer_visible_from: 0.0, veil_drift: 30, veil_cap: 60, confirm_after: 75.0, interrupt_kind: "card", repeat_every: Some(300.0), reentry_default: false },
            Preset::Strict => Policy { grace: 10.0, timer_visible_from: 0.0, veil_drift: 40, veil_cap: 80, confirm_after: 45.0, interrupt_kind: "gate", repeat_every: Some(180.0), reentry_default: true },
        }
    }
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum Focus { OnTask, Drifting, Confirmed, Persisting, Recovering }
#[derive(Clone, Copy, PartialEq, Debug)]
enum EvClass { On, Neutral, Strong }
#[derive(Clone, Copy, PartialEq, Debug)]
enum EvSource { Judgment, Rule, Cache }

/// Highest priority first (spec 3.3, beacon reason when holds overlap).
#[derive(Clone, Copy, PartialEq, Debug)]
enum HoldReason { User = 0, Meeting = 1, Sleep = 2, Idle = 3, Break = 4, Snooze = 5, Sensitive = 6 }
impl HoldReason {
    fn name(self) -> &'static str {
        match self { HoldReason::User => "user", HoldReason::Meeting => "meeting", HoldReason::Sleep => "sleep", HoldReason::Idle => "idle",
                     HoldReason::Break => "break", HoldReason::Snooze => "snooze", HoldReason::Sensitive => "sensitive" }
    }
    fn stops_clock(self) -> bool { self != HoldReason::Snooze && self != HoldReason::Sensitive }
}

#[derive(Clone)]
struct Hold { reason: HoldReason, since: f64, until: Option<f64> }

#[derive(Clone)]
struct Block {
    id: Option<i64>, #[allow(dead_code)] onset: f64, off_accum: f64, running_since: Option<f64>,
    strongs: Vec<(f64, String)>, flagged: bool, ever_flagged: bool, was_confirmed: bool,
    interrupts_in_block: i64, interrupt_due_at: Option<f64>, target_window: Option<String>, target_site: Option<String>,
}
impl Block {
    fn new(onset: f64) -> Block {
        Block { id: None, onset, off_accum: 0.0, running_since: Some(onset), strongs: vec![], flagged: false, ever_flagged: false, was_confirmed: false,
                interrupts_in_block: 0, interrupt_due_at: None, target_window: None, target_site: None }
    }
    fn timer(&self, t: f64) -> f64 { self.off_accum + self.running_since.map_or(0.0, |r| t - r) }
    fn pause(&mut self, t: f64) { if let Some(r) = self.running_since { self.off_accum += t - r; self.running_since = None; } }
}

#[derive(Clone)]
struct Frozen { block: Block, return_at: f64 }
#[derive(Clone, Copy)]
struct Evidence { cls: EvClass, at: f64, from_judgment: bool }
#[derive(Clone)]
struct WindowState { window_key: String, site_key: String, rule_label: Option<Label>, since: f64 }
#[derive(Clone)]
struct OpenSurface { kind: String, at: f64, window_key: String }
#[derive(Clone, Copy)]
struct InFlight { id: i64, at: f64 }
#[derive(Clone, Copy, Default)]
struct Segment { from: i64, to: i64, start_at: f64, seconds: i64 }
#[derive(Clone, Copy, PartialEq)]
enum CacheKind { On, Refused }
#[derive(Clone)]
struct CacheEntry { key: String, kind: CacheKind, at: f64 }
struct Stats { off_topic: f64, unsure: f64, drifts: i64, interrupts: i64, refusals: i64, next_block_id: i64 }
impl Stats { fn new() -> Stats { Stats { off_topic: 0.0, unsure: 0.0, drifts: 0, interrupts: 0, refusals: 0, next_block_id: 1 } } }
#[derive(Clone, PartialEq)]
struct BeaconState { state: String, reason: Option<String> }

struct Session { mode: Mode, duration: f64, policy: Policy, shadow: bool, reentry: bool, sound: bool, check_scale: f64, started_at: f64 }

pub struct Brain {
    last_t: f64, session: Option<Session>, holds: Vec<Hold>, paused_accum: f64, paused_since: Option<f64>, wrap_up_sent: bool,
    focus: Focus, window: Option<WindowState>, block: Option<Block>, frozen: Option<Frozen>, return_pending_since: Option<f64>,
    recovering_since: f64, confirmed_at: f64, last_evidence: Option<Evidence>, last_on_task_window_key: Option<String>, last_resume_at: f64,
    interrupt_open: Option<OpenSurface>, reentry_open: bool, interrupt_history: Vec<f64>, session_rules: Vec<(String, String)>,
    cache: Vec<CacheEntry>, next_check_at: f64, on_streak: usize, neutral_streak: usize, in_flight: Option<InFlight>, next_request_id: i64, minimum_request_id: i64,
    power_constrained: bool, power_critical: bool, stats: Stats, last_timer_seconds: f64, panic_veil: bool, force_clock: bool,
    em_beacon: BeaconState, seg: Segment, em_timer_visible: bool, em_timer_running: bool, em_clock_running: Option<bool>,
    one_shots: Vec<Effect>,
}

impl Default for Brain { fn default() -> Self { Brain::new() } }

impl Brain {
    pub fn new() -> Brain {
        Brain {
            last_t: 0.0, session: None, holds: vec![], paused_accum: 0.0, paused_since: None, wrap_up_sent: false, focus: Focus::OnTask,
            window: None, block: None, frozen: None, return_pending_since: None, recovering_since: 0.0, confirmed_at: 0.0, last_evidence: None,
            last_on_task_window_key: None, last_resume_at: 0.0, interrupt_open: None, reentry_open: false, interrupt_history: vec![],
            session_rules: vec![], cache: vec![], next_check_at: f64::INFINITY, on_streak: 0, neutral_streak: 0, in_flight: None, next_request_id: 1, minimum_request_id: 0,
            power_constrained: false, power_critical: false, stats: Stats::new(), last_timer_seconds: 0.0, panic_veil: false, force_clock: false,
            em_beacon: BeaconState { state: "off".into(), reason: None }, seg: Segment::default(), em_timer_visible: false, em_timer_running: false,
            em_clock_running: None, one_shots: vec![],
        }
    }

    fn is_held(&self) -> bool { !self.holds.is_empty() }
    fn policy(&self) -> Policy { self.session.as_ref().map_or(Policy::of(Preset::Standard), |s| s.policy) }
    fn has_hold(&self, r: HoldReason) -> bool { self.holds.iter().any(|h| h.reason == r) }
    fn clock_stopped(&self) -> bool { self.holds.iter().any(|h| h.reason.stops_clock()) }
    fn rule_for(&self, k: &str) -> bool { self.session_rules.iter().any(|(key, _)| key == k) }
    fn last_cls(&self) -> Option<EvClass> { self.last_evidence.map(|e| e.cls) }

    // MARK: entry point (spec 1.1)
    pub fn step(&mut self, raw_t: f64, event: Event) -> Vec<Effect> {
        let mut starting = false;
        if let Event::SessionStart(cfg) = &event {
            if self.session.is_some() { return vec![]; }
            self.last_t = raw_t.max(self.last_t);
            let lt = self.last_t;
            self.start_session(cfg, lt);
            starting = true;
        } else if self.session.is_none() {
            return vec![];
        }
        let t = raw_t.max(self.last_t);
        self.last_t = t;
        self.one_shots.clear();
        self.expire_interrupt(t);
        if !matches!(event, Event::TaskChanged) { self.settle(t); }
        if self.session.is_some() {
            if !starting { self.apply(&event, t); }
            self.settle(t);
        }
        let mut fx = std::mem::take(&mut self.one_shots);
        fx.extend(self.presentation(t));
        self.one_shots.clear();
        self.panic_veil = false;
        self.force_clock = false;
        // stable sort by emission order
        fx.sort_by_key(|e| e.order());
        fx
    }

    // MARK: session lifecycle
    fn start_session(&mut self, c: &SessionConfig, t: f64) {
        let mut p = Policy::of(c.preset);
        let scale = if c.check_scale.is_finite() && c.check_scale > 0.0 { c.check_scale } else { 1.0 };
        if scale != 1.0 { p.grace = (p.grace * scale).max(8.0); p.confirm_after = (p.confirm_after * scale).max(25.0); }
        self.session = Some(Session { mode: c.mode, duration: c.duration_seconds.unwrap_or(0.0), policy: p, shadow: c.shadow,
                                      reentry: c.reentry_prompt.unwrap_or(p.reentry_default), sound: c.sound, check_scale: scale, started_at: t });
        self.holds.clear(); self.paused_accum = 0.0; self.paused_since = None; self.wrap_up_sent = false;
        self.focus = Focus::OnTask; self.window = None; self.block = None; self.frozen = None; self.return_pending_since = None;
        self.last_evidence = None; self.last_on_task_window_key = None; self.last_resume_at = t;
        self.interrupt_open = None; self.reentry_open = false; self.interrupt_history.clear(); self.session_rules.clear(); self.cache.clear();
        self.next_check_at = f64::INFINITY; self.on_streak = 0; self.neutral_streak = 0; self.in_flight = None; self.next_request_id = 1; self.minimum_request_id = 0;
        self.stats = Stats::new(); self.last_timer_seconds = 0.0;
    }

    fn end_session(&mut self, t: f64) {
        self.close_block(t);
        self.close_frozen();
        self.withdraw_open();
        let a = self.active(t);
        self.one_shots.push(Effect::Summary { active_seconds: a, off_topic_seconds: self.stats.off_topic, unsure_seconds: self.stats.unsure,
                                              drifts: self.stats.drifts, interrupts: self.stats.interrupts, refusals: self.stats.refusals });
        self.session = None;
        self.holds.clear(); self.return_pending_since = None; self.window = None; self.in_flight = None; self.focus = Focus::OnTask;
    }

    fn active(&self, t: f64) -> f64 {
        match &self.session {
            None => 0.0,
            Some(s) => t - s.started_at - self.paused_accum - self.paused_since.map_or(0.0, |p| t - p),
        }
    }

    // MARK: settle (spec 1.1)
    fn settle(&mut self, t: f64) {
        for _ in 0..4 {
            if self.session.is_none() { return; }
            let mut changed = false;

            // S1 hold expiry
            let due: Vec<HoldReason> = self.holds.iter().filter(|h| h.until.map_or(false, |u| u <= t)).map(|h| h.reason).collect();
            if !due.is_empty() {
                for r in due { self.drop_hold(r, t); }
                if self.holds.is_empty() { self.resume(t); }
                changed = true;
            }
            // S2 timed clock
            if let Some(s) = &self.session {
                if s.mode == Mode::Timed && !self.clock_stopped() {
                    let remaining = s.duration - self.active(t);
                    if remaining <= 120.0 && !self.wrap_up_sent { self.wrap_up_sent = true; self.one_shots.push(Effect::WrapUp { remaining }); changed = true; }
                    if remaining <= 0.0 { self.end_session(t); return; }
                }
            }
            // S3 held
            if self.is_held() { if changed { continue; } return; }
            let pol = self.policy();
            // S4 return complete
            if let Some(rp) = self.return_pending_since { if t >= rp + 15.0 { self.enter_recovering(t); changed = true; } }
            // S5 recovering done
            if self.focus == Focus::Recovering && t >= self.recovering_since + 5.0 { self.focus = Focus::OnTask; changed = true; }
            // S6 grace
            if self.focus == Focus::OnTask {
                if let Some(mut b) = self.block.clone() {
                    if b.timer(t) >= pol.grace {
                        if b.id.is_none() { b.id = Some(self.stats.next_block_id); self.stats.next_block_id += 1; }
                        self.block = Some(b); self.focus = Focus::Drifting; changed = true;
                    }
                }
            }
            // S7 confirm
            if self.focus == Focus::Drifting && self.return_pending_since.is_none() {
                if let Some(mut b) = self.block.clone() {
                    if b.timer(t) >= pol.confirm_after && Self::has_independent_pair(&b) && self.last_cls() == Some(EvClass::Strong) {
                        if !b.was_confirmed {
                            b.was_confirmed = true; b.interrupt_due_at = Some(t);
                            self.focus = Focus::Confirmed; self.confirmed_at = t;
                        } else {
                            let last_i = self.interrupt_history.last().copied().unwrap_or(f64::NEG_INFINITY);
                            b.interrupt_due_at = pol.repeat_every.map(|r| t.max(last_i + r));
                            self.focus = Focus::Persisting;
                        }
                        self.block = Some(b); changed = true;
                    }
                }
            }
            // S8 interrupt due
            if self.interrupt_due(t) { changed = true; }
            // S9 persist
            if self.focus == Focus::Confirmed && t >= self.confirmed_at + 12.0 { self.focus = Focus::Persisting; changed = true; }
            // S10 cadence
            if self.cadence_due(t) { changed = true; }

            if !changed { return; }
        }
    }

    fn has_independent_pair(b: &Block) -> bool {
        let s = &b.strongs;
        if s.len() < 2 { return false; }
        for i in 0..s.len() {
            for j in (i + 1)..s.len() {
                let d = s[j].0 - s[i].0;
                let ok = if s[j].1 != s[i].1 { d >= 10.0 } else { d >= 20.0 };
                if ok { return true; }
            }
        }
        false
    }

    fn enter_recovering(&mut self, t: f64) {
        let rp = match self.return_pending_since { Some(r) => r, None => return };
        let mut b = match self.block.clone() { Some(b) => b, None => { self.return_pending_since = None; return; } };
        b.pause(rp);
        self.last_timer_seconds = b.timer(t);
        self.frozen = Some(Frozen { block: b.clone(), return_at: rp });
        self.block = None; self.return_pending_since = None;
        self.focus = Focus::Recovering; self.recovering_since = t;
        if let Some(o) = self.interrupt_open.take() { self.one_shots.push(Effect::Withdraw { what: o.kind }); }
        if b.was_confirmed && self.session.as_ref().map_or(false, |s| s.reentry) {
            self.reentry_open = true;
            self.one_shots.push(Effect::ReentryPrompt { block: b.id.unwrap_or(0) });
        }
    }

    // S8 (spec 4.7). Returns true if state changed.
    fn interrupt_due(&mut self, t: f64) -> bool {
        let (shadow, sound, pol) = match &self.session { Some(s) => (s.shadow, s.sound, s.policy), None => return false };
        if !(self.focus == Focus::Confirmed || self.focus == Focus::Persisting) || self.return_pending_since.is_some() { return false; }
        let mut b = match self.block.clone() { Some(b) => b, None => return false };
        let due_at = match b.interrupt_due_at { Some(d) if d <= t => d, _ => return false };
        if self.last_cls() != Some(EvClass::Strong) { return false; }
        let wk = match &self.window { Some(w) => w.window_key.clone(), None => return false };
        if !shadow {
            if let Some(open) = &self.interrupt_open {
                if open.kind == "gate" { if let Some(r) = pol.repeat_every { b.interrupt_due_at = Some(due_at + r); self.block = Some(b); return true; } }
                return false; // never stacked: wait for the card or notice to expire
            }
            let recent: Vec<f64> = self.interrupt_history.iter().copied().filter(|&h| h > t - 600.0 && h <= t).collect();
            if recent.len() >= 2 {
                let min = recent.iter().copied().fold(f64::INFINITY, f64::min);
                b.interrupt_due_at = Some(min + 600.0); self.block = Some(b); return true;
            }
            let severity = if b.interrupts_in_block == 0 { 1 } else { 2 };
            self.one_shots.push(Effect::Interrupt { kind: pol.interrupt_kind.into(), severity, block: b.id.unwrap_or(0), window_key: wk.clone() });
            if sound { self.one_shots.push(Effect::Cue); }
            self.interrupt_open = Some(OpenSurface { kind: pol.interrupt_kind.into(), at: t, window_key: wk });
            self.interrupt_history.push(t);
            self.stats.interrupts += 1;
        } else {
            self.one_shots.push(Effect::ShadowMark { block: b.id.unwrap_or(0), kind: pol.interrupt_kind.into(), window_key: wk });
        }
        b.interrupts_in_block += 1;
        b.interrupt_due_at = pol.repeat_every.map(|r| t + r);
        self.block = Some(b);
        true
    }

    // S10 (spec 6.2)
    fn cadence_due(&mut self, t: f64) -> bool {
        let w = match &self.window { Some(w) => w.clone(), None => return false };
        if !(self.next_check_at <= t) || self.power_critical { return false; }
        if let Some(f) = self.in_flight { if t - f.at < 15.0 { return false; } }
        if self.rule_for(&w.window_key) || self.rule_for(&w.site_key) { return false; }
        if w.rule_label == Some(Label::OnTask) || w.rule_label == Some(Label::Unsure) { return false; }
        if let Some(c) = self.cache_entry(&w.window_key) { if c.kind == CacheKind::Refused && t - c.at < 900.0 { return false; } }
        let urgency = if self.block.as_ref().map_or(false, |b| b.flagged) { "high" } else { "normal" };
        self.request_judgment("cadence", urgency, t);
        true
    }

    fn request_judgment(&mut self, reason: &str, urgency: &str, t: f64) {
        let w = match &self.window { Some(w) => w.clone(), None => return };
        let id = self.next_request_id; self.next_request_id += 1;
        self.in_flight = Some(InFlight { id, at: t });
        self.next_check_at = f64::INFINITY;
        self.one_shots.push(Effect::RequestJudgment { id, reason: reason.into(), urgency: urgency.into(), window_key: w.window_key, allow_vision: !self.power_constrained });
    }

    // MARK: holds (spec 3.3)
    fn add_hold(&mut self, r: HoldReason, until: Option<f64>, t: f64) {
        let was_held = self.is_held();
        let was_stopped = self.clock_stopped();
        self.holds.retain(|h| h.reason != r);
        self.holds.push(Hold { reason: r, since: t, until });
        if !was_stopped && r.stops_clock() { self.paused_since = Some(t); }
        if r == HoldReason::Sensitive {
            if !was_held { self.freeze_block(t); }
            self.window = None;
        } else {
            self.close_block(t);
            self.close_frozen();
        }
        self.next_check_at = f64::INFINITY; self.in_flight = None; self.return_pending_since = None; self.focus = Focus::OnTask;
        self.withdraw_open();
    }

    fn drop_hold(&mut self, r: HoldReason, t: f64) {
        if !self.has_hold(r) { return; }
        let was_stopped = self.clock_stopped();
        self.holds.retain(|h| h.reason != r);
        if was_stopped && !self.clock_stopped() {
            if let Some(ps) = self.paused_since { self.paused_accum += t - ps; self.paused_since = None; }
        }
        if r == HoldReason::Sensitive { self.window = None; }
    }

    fn remove_hold(&mut self, r: HoldReason, t: f64) {
        self.drop_hold(r, t);
        if self.holds.is_empty() { self.resume(t); }
    }

    fn resume(&mut self, t: f64) {
        self.focus = Focus::OnTask;
        self.last_resume_at = t;
        if self.window.is_some() { self.window.as_mut().unwrap().since = t; self.evaluate_window(t, "resume"); }
    }

    fn close_block(&mut self, t: f64) {
        if let Some(b) = self.block.take() { self.last_timer_seconds = b.timer(t); self.count(&b, t); }
    }
    fn close_frozen(&mut self) {
        if let Some(f) = self.frozen.take() { self.last_timer_seconds = f.block.timer(0.0); self.count(&f.block, 0.0); }
    }
    fn freeze_block(&mut self, t: f64) {
        let mut b = match self.block.take() { Some(b) => b, None => return };
        b.pause(t);
        self.last_timer_seconds = b.timer(t);
        self.frozen = Some(Frozen { block: b, return_at: t });
    }
    fn count(&mut self, b: &Block, t: f64) {
        if b.id.is_none() { return; }
        let tm = b.timer(t);
        if b.ever_flagged { self.stats.off_topic += tm; self.stats.drifts += 1; } else { self.stats.unsure += tm; }
    }

    fn withdraw_open(&mut self) {
        if let Some(o) = self.interrupt_open.take() { self.one_shots.push(Effect::Withdraw { what: o.kind }); }
        if self.reentry_open { self.one_shots.push(Effect::Withdraw { what: "reentry".into() }); self.reentry_open = false; }
    }

    fn expire_interrupt(&mut self, t: f64) {
        if let Some(o) = &self.interrupt_open { if o.kind != "gate" && t >= o.at + 12.0 { self.interrupt_open = None; } }
    }

    // MARK: events (spec 2, 4)
    fn apply(&mut self, event: &Event, t: f64) {
        match event {
            Event::SessionStart(_) | Event::Tick => {}
            Event::SessionEnd => self.end_session(t),
            Event::TaskChanged => {
                self.close_block(t); self.close_frozen(); self.withdraw_open();
                self.focus = Focus::OnTask; self.window = None; self.last_evidence = None; self.last_on_task_window_key = None;
                self.return_pending_since = None; self.last_resume_at = t; self.last_timer_seconds = 0.0;
                self.cache.clear(); self.session_rules.clear(); self.in_flight = None; self.next_check_at = f64::INFINITY;
                self.minimum_request_id = self.next_request_id; self.on_streak = 0; self.neutral_streak = 0;
            },
            Event::Judgment(j) => self.on_judgment(j, t),
            Event::WindowChange(w) => self.on_window_change(w, t),
            Event::UserAction(a, minutes) => self.on_user_action(*a, *minutes, t),
            Event::Idle => self.add_hold(HoldReason::Idle, None, t),
            Event::Sleep => self.add_hold(HoldReason::Sleep, None, t),
            Event::Active => self.wake_from(HoldReason::Idle, t),
            Event::Wake => self.wake_from(HoldReason::Sleep, t),
            Event::MeetingStart => self.add_hold(HoldReason::Meeting, None, t),
            Event::MeetingEnd => { if self.has_hold(HoldReason::Meeting) { self.one_shots.push(Effect::AskResume { reason: "meeting".into() }); } }
            Event::SensitiveEntered => self.add_hold(HoldReason::Sensitive, None, t),
            Event::SensitiveLeft => self.remove_hold(HoldReason::Sensitive, t),
            Event::PowerChange { constrained, critical } => { self.power_constrained = *constrained; self.power_critical = *critical; }
        }
    }

    /// Idle and sleep: a short absence resumes silently, a long one asks (spec 3.3, 300 s).
    fn wake_from(&mut self, r: HoldReason, t: f64) {
        let since = match self.holds.iter().find(|h| h.reason == r) { Some(h) => h.since, None => return };
        if t - since < 300.0 { self.remove_hold(r, t); } else { self.one_shots.push(Effect::AskResume { reason: r.name().into() }); }
    }

    fn on_window_change(&mut self, w: &WindowChangeInput, t: f64) {
        self.window = Some(WindowState { window_key: w.window_key.clone(), site_key: w.site_key.clone(), rule_label: w.rule_label, since: t });
        if self.is_held() { return; }
        self.evaluate_window(t, "window_change");
    }

    fn cache_entry(&self, key: &str) -> Option<&CacheEntry> { self.cache.iter().find(|c| c.key == key) }

    fn write_cache(&mut self, key: &str, kind: CacheKind, t: f64) {
        self.cache.retain(|c| c.key != key);
        self.cache.push(CacheEntry { key: key.into(), kind, at: t });
        if self.cache.len() > 256 {
            let mut oldest = 0;
            for i in 1..self.cache.len() {
                let (a, b) = (&self.cache[i], &self.cache[oldest]);
                if a.at < b.at || (a.at == b.at && a.key.as_bytes() < b.key.as_bytes()) { oldest = i; }
            }
            self.cache.remove(oldest);
        }
    }

    /// Spec 4.1, also used by resume.
    fn evaluate_window(&mut self, t: f64, reason: &str) {
        let w = match &self.window { Some(w) => w.clone(), None => return };
        self.on_streak = 0; self.neutral_streak = 0;
        if let Some(g) = &self.interrupt_open {
            if g.kind == "gate" && g.window_key != w.window_key { self.one_shots.push(Effect::Withdraw { what: "gate".into() }); self.interrupt_open = None; }
        }
        if self.rule_for(&w.window_key) || self.rule_for(&w.site_key) {
            self.apply_evidence(EvClass::On, t, t, &w, "", EvSource::Rule); return;
        }
        if let Some(rl) = w.rule_label {
            match rl {
                Label::OnTask => self.apply_evidence(EvClass::On, t, t, &w, "", EvSource::Rule),
                Label::Unsure => self.apply_evidence(EvClass::Neutral, t, t, &w, "", EvSource::Rule),   // never-judged windows: no model call
                Label::OffTask => { let k = format!("rule:{}", w.window_key); self.apply_evidence(EvClass::Strong, t, t, &w, &k, EvSource::Rule) }
            }
            return;
        }
        if let Some(c) = self.cache_entry(&w.window_key).cloned() {
            if t - c.at < 900.0 {
                if c.kind == CacheKind::On { self.apply_evidence(EvClass::On, t, t, &w, "", EvSource::Cache) }
                else { self.apply_evidence(EvClass::Neutral, t, t, &w, "", EvSource::Cache) }
                return;
            }
        }
        self.request_judgment(reason, "now", t);
    }

    fn on_judgment(&mut self, j: &JudgmentInput, t: f64) {
        let w = match (&self.session, &self.window) { (Some(_), Some(w)) => w.clone(), _ => return };
        if j.request_id.is_some_and(|id| id < self.minimum_request_id) { return; }
        let is_refusal = j.flag != Flag::None;
        if self.is_held() {
            // Held: ignored, except an ON result still refreshes the cache (never while a sensitive window is up).
            if !self.has_hold(HoldReason::Sensitive) && j.window_key == w.window_key && !is_refusal && j.label == Label::OnTask && j.source != JSource::Rule {
                self.write_cache(&j.window_key, CacheKind::On, t);
            }
            return;
        }
        if !(j.window_key == w.window_key && j.observed_at >= w.since && j.observed_at >= self.last_resume_at) { return; }
        if let Some(le) = self.last_evidence { if le.from_judgment && j.observed_at < le.at { return; } }
        if self.rule_for(&w.window_key) || self.rule_for(&w.site_key) { return; }
        if let Some(f) = self.in_flight { if j.request_id.is_none() || j.request_id == Some(f.id) { self.in_flight = None; } }

        let cls;
        if is_refusal {
            self.stats.refusals += 1;
            self.write_cache(&j.window_key, CacheKind::Refused, t);
            cls = EvClass::Neutral;
        } else {
            cls = match j.label {
                Label::OnTask => { self.write_cache(&j.window_key, CacheKind::On, t); EvClass::On }
                Label::Unsure => EvClass::Neutral,
                Label::OffTask => if j.strong { EvClass::Strong } else { EvClass::Neutral },
            };
        }
        self.apply_evidence(cls, j.observed_at, t, &w, &j.content_key, EvSource::Judgment);
    }

    // MARK: evidence (spec 4.3)
    fn apply_evidence(&mut self, c: EvClass, o: f64, t: f64, w: &WindowState, content_key: &str, source: EvSource) {
        if c == EvClass::On { self.last_on_task_window_key = Some(w.window_key.clone()); }
        match self.focus {
            Focus::Recovering => { if c != EvClass::On { self.focus = Focus::OnTask; self.evidence_while_on_task(c, o, t, w, content_key); } }
            Focus::OnTask => self.evidence_while_on_task(c, o, t, w, content_key),
            Focus::Drifting | Focus::Confirmed | Focus::Persisting => self.evidence_while_drifting(c, o, t, w, content_key),
        }
        self.last_evidence = Some(Evidence { cls: c, at: o, from_judgment: source == EvSource::Judgment });
        self.schedule_next(c, source, t);
    }

    fn start_block(&mut self, o: f64) {
        if let Some(f) = self.frozen.clone() {
            if o - f.return_at <= 120.0 {
                let mut b = f.block;
                b.running_since = Some(o); b.strongs.clear(); b.flagged = false;
                self.block = Some(b); self.frozen = None;
                return;
            }
        }
        self.close_frozen();
        self.block = Some(Block::new(o));
    }

    fn add_strong(&mut self, o: f64, w: &WindowState, key: &str) {
        let push = self.focus == Focus::OnTask || self.focus == Focus::Drifting;
        if let Some(b) = self.block.as_mut() {
            b.flagged = true; b.ever_flagged = true;
            if push { b.strongs.push((o, key.to_string())); }
            b.target_window = Some(w.window_key.clone()); b.target_site = Some(w.site_key.clone());
        }
    }

    fn evidence_while_on_task(&mut self, c: EvClass, o: f64, t: f64, w: &WindowState, key: &str) {
        match c {
            EvClass::On => { if let Some(b) = self.block.take() { self.last_timer_seconds = b.timer(t); } } // a candidate that never reached grace is dropped
            EvClass::Neutral => { if self.block.is_none() { self.start_block(o); } }
            EvClass::Strong => { if self.block.is_none() { self.start_block(o); } self.add_strong(o, w, key); }
        }
    }

    fn evidence_while_drifting(&mut self, c: EvClass, o: f64, t: f64, w: &WindowState, key: &str) {
        match c {
            EvClass::On => {
                if self.return_pending_since.is_none() {
                    self.return_pending_since = Some(t);
                    if let Some(b) = self.block.as_mut() { b.pause(t); b.strongs.clear(); }
                }
            }
            EvClass::Neutral => self.cancel_return(o),
            EvClass::Strong => { self.cancel_return(o); self.add_strong(o, w, key); }
        }
    }

    fn cancel_return(&mut self, o: f64) {
        if let Some(rp) = self.return_pending_since {
            if let Some(b) = self.block.as_mut() { b.running_since = Some(o.max(rp)); }
            self.return_pending_since = None;
        }
    }

    /// Spec 6.2: when to ask again.
    fn schedule_next(&mut self, c: EvClass, source: EvSource, t: f64) {
        if c == EvClass::On {
            if source == EvSource::Cache { self.on_streak = 3; } else if source == EvSource::Judgment { self.on_streak += 1; }
        }
        let interval: Option<f64>;
        let flagged = self.block.as_ref().map_or(false, |b| b.flagged);
        if (self.focus == Focus::Confirmed || self.focus == Focus::Persisting) && self.return_pending_since.is_none() { interval = Some(30.0); }
        else if self.return_pending_since.is_some() { interval = Some(10.0); }
        else if c == EvClass::On && source != EvSource::Judgment && source != EvSource::Cache { interval = None; } // rule: deterministic
        else if c == EvClass::On && source == EvSource::Cache { interval = Some(90.0); }
        else if c == EvClass::On { interval = Some([30.0, 60.0, 90.0][self.on_streak.min(3) - 1]); }
        else if c == EvClass::Strong || flagged { interval = Some(10.0); }
        else { self.neutral_streak += 1; interval = Some([10.0, 20.0, 40.0, 60.0][self.neutral_streak.min(4) - 1]); }
        let scale = self.session.as_ref().map_or(1.0, |s| s.check_scale);
        self.next_check_at = match interval { Some(i) => t + (i * scale).max(4.0) * if self.power_constrained { 2.0 } else { 1.0 }, None => f64::INFINITY };
    }

    // MARK: user actions (spec 2.3)
    fn on_user_action(&mut self, a: UserAction, minutes: Option<i64>, t: f64) {
        match a {
            UserAction::Pause => self.add_hold(HoldReason::User, None, t),
            UserAction::Resume => {
                if !self.is_held() { return; }
                let rs: Vec<HoldReason> = self.holds.iter().map(|h| h.reason).filter(|&r| r != HoldReason::Sensitive).collect();
                for r in rs { self.drop_hold(r, t); }
                if self.holds.is_empty() { self.resume(t); }
            }
            UserAction::Snooze => self.add_hold(HoldReason::Snooze, minutes.map(|m| t + 60.0 * m as f64), t),
            UserAction::BreakTime => self.add_hold(HoldReason::Break, Some(t + 60.0 * minutes.unwrap_or(5) as f64), t),
            UserAction::Extend => {
                let (is_timed, new_duration) = match &self.session { Some(s) => (s.mode == Mode::Timed, s.duration + 60.0 * minutes.unwrap_or(5) as f64), None => return };
                if !is_timed { return; }
                if let Some(s) = self.session.as_mut() { s.duration = new_duration; }
                self.force_clock = true;
                if new_duration - self.active(t) > 120.0 { self.wrap_up_sent = false; }
            }
            UserAction::End => self.end_session(t),
            UserAction::ThatWasFine => {
                let (w, _) = self.target();
                self.forgive(t, ("allow", w.clone()), &w.clone(), "project", "allow", "window", &w);
            }
            UserAction::MarkRelevant => {
                let (w, s) = self.target();
                self.forgive(t, ("allow", s.clone()), &w, "project", "allow", "site", &s);
            }
            UserAction::IgnoreWindow => {
                let (w, _) = self.target();
                self.forgive(t, ("ignore", w.clone()), &w.clone(), "session", "ignore", "window", &w);
            }
            UserAction::MarkOffTask => {
                if let Some(s) = self.window.as_ref().map(|w| w.site_key.clone()) {
                    self.one_shots.push(Effect::LearnRule { scope: "project".into(), kind: "deny".into(), key_type: "site".into(), key: s });
                }
            }
            UserAction::BackToTask => {
                if let Some(o) = self.interrupt_open.take() { self.one_shots.push(Effect::Withdraw { what: o.kind }); }
                self.one_shots.push(Effect::BringBack { window_key: self.last_on_task_window_key.clone() });
            }
            UserAction::Dismiss => {
                if let Some(o) = self.interrupt_open.take() { self.one_shots.push(Effect::Withdraw { what: o.kind }); }
                else if self.reentry_open { self.one_shots.push(Effect::Withdraw { what: "reentry".into() }); self.reentry_open = false; }
            }
            UserAction::NextStep => {
                if self.reentry_open { self.one_shots.push(Effect::Withdraw { what: "reentry".into() }); self.reentry_open = false; }
            }
            UserAction::Panic => { self.add_hold(HoldReason::User, None, t); self.panic_veil = true; }
        }
    }

    fn target(&self) -> (String, String) {
        let w = self.block.as_ref().and_then(|b| b.target_window.clone()).or_else(|| self.window.as_ref().map(|w| w.window_key.clone())).unwrap_or_default();
        let s = self.block.as_ref().and_then(|b| b.target_site.clone()).or_else(|| self.window.as_ref().map(|w| w.site_key.clone())).unwrap_or_else(|| w.clone());
        (w, s)
    }

    /// Spec 4.8.
    fn forgive(&mut self, t: f64, rule: (&str, String), key: &str, scope: &str, kind: &str, key_type: &str, rule_key: &str) {
        if let Some(b) = &self.block { self.last_timer_seconds = b.timer(t); } else if let Some(f) = &self.frozen { self.last_timer_seconds = f.block.timer(0.0); }
        self.block = None; self.frozen = None; self.return_pending_since = None; self.focus = Focus::OnTask; self.last_evidence = None;
        self.session_rules.retain(|(k, _)| k != rule_key);
        self.session_rules.push((rule_key.to_string(), rule.0.to_string()));
        self.write_cache(key, CacheKind::On, t);
        self.next_check_at = f64::INFINITY;
        self.withdraw_open();
        self.one_shots.push(Effect::LearnRule { scope: scope.into(), kind: kind.into(), key_type: key_type.into(), key: rule_key.into() });
    }

    // MARK: presentation (spec 5.1)
    fn beacon_now(&self) -> BeaconState {
        let s = match &self.session { Some(s) => s, None => return BeaconState { state: "off".into(), reason: None } };
        if let Some(top) = self.holds.iter().map(|h| h.reason).min_by_key(|r| *r as i32) { return BeaconState { state: "paused".into(), reason: Some(top.name().into()) }; }
        let rest = BeaconState { state: "resting".into(), reason: None };
        if s.shadow { return rest; }
        match self.focus {
            Focus::OnTask => rest,
            Focus::Drifting => BeaconState { state: if self.block.as_ref().map_or(false, |b| b.flagged) { "drifting" } else { "watching" }.into(), reason: None },
            Focus::Confirmed | Focus::Persisting => BeaconState { state: "interrupted".into(), reason: None },
            Focus::Recovering => BeaconState { state: "recovering".into(), reason: None },
        }
    }

    fn level(s: &Segment, t: f64) -> i64 {
        if s.seconds == 0 || t - s.start_at >= s.seconds as f64 { return s.to; }
        let elapsed = t - s.start_at;
        if s.to >= s.from { s.from + (((s.to - s.from) as f64 * elapsed) / s.seconds as f64).floor() as i64 }
        else { s.from - (((s.from - s.to) as f64 * elapsed) / s.seconds as f64).floor() as i64 }
    }

    fn veil_target(&self, t: f64) -> i64 {
        let s = match &self.session { Some(s) if !self.is_held() && !s.shadow => s, _ => return 0 };
        if self.return_pending_since.is_some() { return Self::level(&self.seg, t); }
        match self.focus {
            Focus::Drifting => if self.block.as_ref().map_or(false, |b| b.flagged) { s.policy.veil_drift } else { 0 },
            Focus::Confirmed | Focus::Persisting => s.policy.veil_cap,
            _ => 0,
        }
    }

    fn presentation(&mut self, t: f64) -> Vec<Effect> {
        let mut fx = vec![];
        let b = self.beacon_now();
        if b != self.em_beacon { fx.push(Effect::Beacon { state: b.state.clone(), reason: b.reason.clone() }); self.em_beacon = b; }

        let target = self.veil_target(t);
        if target != self.seg.to {
            let from = Self::level(&self.seg, t);
            let secs = if target == 0 { if self.panic_veil { 0 } else { 5 } } else { (target - from).abs() }; // impl: abs, 1 %/s either direction
            fx.push(Effect::Veil { from, to: target, seconds: secs });
            self.seg = Segment { from, to: target, start_at: t, seconds: secs };
        }

        let mut visible = false;
        if let Some(s) = &self.session {
            if !self.is_held() && !s.shadow && (self.focus == Focus::Drifting || self.focus == Focus::Confirmed || self.focus == Focus::Persisting) {
                if let Some(blk) = &self.block { if blk.flagged && blk.timer(t) >= s.policy.timer_visible_from { visible = true; } }
            }
        }
        let running = self.block.as_ref().map_or(false, |b| b.running_since.is_some());
        if visible != self.em_timer_visible || (visible && running != self.em_timer_running) {
            let secs = self.block.as_ref().map_or(self.last_timer_seconds, |b| b.timer(t));
            fx.push(Effect::OffTopicTimer { seconds: secs, running, visible });
        }
        self.em_timer_visible = visible; self.em_timer_running = running;

        if let Some(s) = &self.session {
            let run = !self.clock_stopped();
            if self.em_clock_running.is_none() || Some(run) != self.em_clock_running || self.force_clock {
                let a = self.active(t);
                fx.push(Effect::Clock { seconds: if s.mode == Mode::Timed { s.duration - a } else { a }, running: run });
            }
            self.em_clock_running = Some(run);
        } else {
            self.em_clock_running = None;
        }
        fx
    }
}
