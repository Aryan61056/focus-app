# Brain spec: the focus state machine

Draft 0.1 · 2026-10-01 · Status: **proposal for owner review**. Nothing here is built or run.

The brain is the shared core from PLAN 7.1: a pure function `step(state, event) -> (state, [effects])`.
This spec is precise enough that two implementations (Swift now; Rust or C# later, see spike S5) must produce
identical golden traces (section 9). Where this spec and PLAN.md differ, this spec says so and why.
Every number marked **ST** is a starting target to tune against measurements (PLAN 9.3), not a fact.

**What changed from PLAN because of S1** (`docs/S1-accuracy.md`, and the owner's 2026-10-01 decision to use
Apple's system model on Mac):

| PLAN assumption | Reality on Mac | Consequence here |
|---|---|---|
| Verdicts carry a calibrated confidence (B4, 4.2) | No log-probs; stated confidence is 90-95 on nearly every call | The brain never reads a confidence number. It reads a `strong` flag (section 2.2) |
| One judgment is enough evidence | Single pass is about 50% strict precision; it over-flags neutral moments (music, messages, new tab) | A moment counts toward a nudge only when two framings agree (`strong`), and only after time and repetition (section 4.4) |
| Text judge under 2 s | About 3.5 s per judgment at realistic spacing | Cadence and timers assume 3.5 s latency (section 6) |
| Two-judge rule gives high precision | 71-79% strict precision per moment, intervals 52-92% | The brain does not trust any single moment. Time, repetition, rules and corrections make up the gap. Shadow mode stays the first-run default |

---

## 1. Time model and determinism

| Rule | Detail |
|---|---|
| Time unit | Seconds, IEEE-754 binary64 (`Double`). Every event carries `t`. |
| Origin | Any monotonic origin. Golden traces start the session at `t = 0`. The body converts from the OS monotonic clock; wall-clock time never enters the brain. |
| No hidden inputs | The brain never reads a clock, a random source, the environment, or a hash-map iteration order. All collections that affect output are ordered (insertion order or sorted by key, as stated). |
| Ordering | Events are processed in arrival order. If `t` is less than the last processed `t`, the brain uses the last processed `t` instead (clamp, no error). Equal `t` is allowed. |
| Ticks | While a session exists, the body sends `Tick` every 1.0 s on the integer-second grid. Ticks carry no data; they let deadlines fire. A deadline at 118.5 fires at the first event with `t >= 118.5`, normally the tick at 119, and the transition is stamped with that event's `t`, not with the deadline. |
| Comparisons | Deadlines use `t >= deadline`. Durations are `t - start` evaluated exactly as written. No fused multiply-add, no reordering of floating-point expressions. Golden-trace inputs use multiples of 0.25 s, which are exact in binary64. |
| Integers | Veil levels are integer percent (0-100). IDs (`requestId`, `block`) are integers counting from 1 per session. |
| Floor | `floor` is mathematical floor of a binary64 value. Used only for the veil level (section 5.3). |
| Output numbers | Effects carry binary64 numbers. Trace comparison treats numbers as equal when `abs(a - b) <= 1e-6`. Strings and booleans compare exactly. |
| Effects per event | At most one effect of each type per event, emitted in the fixed order of section 5.2. |

### 1.1 Processing one event

```
step(state, event):
  t := max(event.t, state.lastT)
  before := presentation(state, t)          # section 5.1
  settle(state, t)                          # fire due deadlines first
  apply(state, event, t)                    # event-specific rules, sections 2 and 4
  settle(state, t)                          # conditions the event may have made true
  effects := oneShots(collected in order) + diff(before, presentation(state, t))
  sort effects by the order in section 5.2
```

`settle(t)` evaluates these rules in this order, and repeats the whole list until a pass changes nothing (at most 4 passes):

| # | Rule | Fires when |
|---|---|---|
| S1 | Hold expiry | `break` or `snooze` hold has `until <= t`: remove it. If no hold remains, run **resume** (section 3.3). |
| S2 | Timed clock | Mode Timed, not paused: `remaining <= 120` and wrap-up not sent → one-shot `WrapUp`. `remaining <= 0` → end the session (section 3.3, end). |
| S3 | Held | If any hold is active, stop here (S4-S10 do not run). |
| S4 | Return complete | `returnPendingSince != nil` and `t >= returnPendingSince + 15` → enter **Recovering**. |
| S5 | Recovering done | Focus is Recovering and `t >= recoveringSince + 5` → focus **OnTask**. |
| S6 | Grace | Focus is OnTask, a block exists, and `timer(t) >= preset.grace` → focus **Drifting**. |
| S7 | Confirm | Section 4.4 conditions all hold → focus **Confirmed** (or **Persisting**, see 4.6). |
| S8 | Interrupt due | Section 4.7 conditions all hold → one-shot `Interrupt`. |
| S9 | Persist | Focus is Confirmed and `t >= confirmedAt + 12` → focus **Persisting** (no visible change). |
| S10 | Cadence | Section 6.2 conditions hold → one-shot `RequestJudgment`. |

---

## 2. Events

All events have `t: Double`. Field defaults used by golden traces are in section 9.1.

| Event | Fields | Sent by |
|---|---|---|
| `SessionStart` | `sessionId: String`, `taskId: String`, `mode: Timed\|Open`, `durationSeconds: Double?` (Timed only), `preset: Gentle\|Standard\|Strict`, `shadow: Bool`, `reentryPrompt: Bool?` (null = preset default), `sound: Bool` | body |
| `SessionEnd` | `reason: user\|timer` (the brain generates `timer` itself; the body only sends `user`) | body |
| `Tick` | none | body, 1 Hz while a session exists |
| `Judgment` | `requestId: Int?`, `observedAt: Double` (when the window was captured), `windowKey`, `contentKey`, `label: on_task\|unsure\|off_task`, `strong: Bool`, `source: model\|unchanged\|rule`, `flag: none\|refusal\|error` | senses |
| `WindowChange` | `windowKey`, `siteKey`, `ruleLabel: on_task\|off_task\|null` (stage 1 project rules) | senses, only when `windowKey` changes |
| `UserAction` | `action` (table 2.3), `minutes: Int?` | body |
| `Idle` / `Active` | none. `Idle` is sent after 120 s **ST** without input, unless the senses detect reading (B7) or media playing | senses |
| `Sleep` / `Wake` | none. Screen lock and display-off map to `Sleep` | body |
| `MeetingStart` / `MeetingEnd` | none (D10 signals: camera or mic in use, conferencing app frontmost, presenting) | senses |
| `SensitiveEntered` / `SensitiveLeft` | none. No keys, no title: a sensitive window is never described to the brain. A `WindowChange` always follows `SensitiveLeft` | senses (stage 0) |
| `PowerChange` | `constrained: Bool` (Low Power Mode, Energy Saver, low battery, thermal serious), `critical: Bool` (thermal critical) | body |

### 2.1 Keys

| Key | Granularity | Example | Used for |
|---|---|---|---|
| `siteKey` | app, or app plus registrable domain | `chrome\|youtube.com` | `mark_relevant`, project rules |
| `windowKey` | `siteKey` plus normalized title and URL path | `chrome\|youtube.com/watch?v=abc` | identity of "the window", cache, staleness, `that_was_fine`, `ignore_window` |
| `contentKey` | `windowKey` plus a digest of what was judged (text digest or perceptual-hash bucket) | `...abc#7f3e` | independence of strong verdicts |

Keys are opaque strings to the brain. Confidential projects (J15) hash titles inside the keys; the brain does not care.

### 2.2 Judgment classes

The brain maps every piece of evidence to one of three classes. Nothing else about a judgment matters to the state machine.

| Class | Judgment | Effect on the state machine |
|---|---|---|
| **ON** | `label = on_task`; or a session allow/ignore rule; or `ruleLabel = on_task`; or a fresh ON cache entry | Cancels a candidate, starts a return, clears strong evidence |
| **NEUTRAL** | `label = unsure`; `label = off_task` with `strong = false`; any `flag != none` (label and strong are then ignored); a fresh REFUSED cache entry | Can start a block and keep it Drifting. **Never** counts toward confirmation, never interrupts, never sets `flagged` |
| **STRONG** | `label = off_task` with `strong = true` and `flag = none`; or `ruleLabel = off_task` (the user's own "always off" list) | Sets `flagged`, counts toward the independent pair |

How the Mac judge fills `strong` (senses-side, recorded here so both sides agree; A = reason-first framing, B = relation framing, the S1 two-judge rule):

| A says | B says | `label` | `strong` |
|---|---|---|---|
| off_task | off_task or unsure | off_task | true |
| off_task | on_task | off_task | false |
| unsure | anything | unsure | false |
| on_task | on_task or unsure | on_task | false |
| on_task | off_task | unsure | false |

A Windows runtime that has calibrated probabilities may set `strong` from them instead. The brain does not change.

### 2.3 User actions

| `action` | Effect (all apply only during a session; otherwise ignored) |
|---|---|
| `pause` | Add hold `user`. |
| `resume` | Remove every hold except `sensitive`; close any pending `AskResume`; run **resume**. No-op when not held. |
| `snooze` | `minutes` in {15, 30, 60} or null (rest of session). Add hold `snooze` until `t + 60*minutes` (or forever). |
| `break` | `minutes` in {5, 10, 15}. Add hold `break` until `t + 60*minutes`. Auto-resumes (S1). |
| `extend` | Timed only: `durationSeconds += 60*minutes`; emit `Clock`; if `remaining > 120`, allow `WrapUp` again. Open: no-op. |
| `end` | Same as `SessionEnd{reason: user}`. |
| `that_was_fine` | Forgive the current block (4.8). `LearnRule{scope: project, kind: allow, keyType: window, key: target}`. |
| `mark_relevant` | Forgive the current block. `LearnRule{scope: project, kind: allow, keyType: site, key: target's siteKey}`. |
| `ignore_window` | Forgive the current block. `LearnRule{scope: session, kind: ignore, keyType: window, key: target}`. The window counts as ON for the rest of the session and is never judged. |
| `mark_off_task` | `LearnRule{scope: project, kind: deny, keyType: site, key: current siteKey}`. No state change: the user already knows. |
| `back_to_task` | `BringBack{windowKey: lastOnTaskWindowKey}` (null if none); withdraw any open interrupt. **Not** evidence: the `WindowChange` that follows is. |
| `dismiss` | Withdraw the open interrupt, else the open re-entry prompt. No other change; the repeat schedule stands. |
| `next_step` | The user answered or skipped the re-entry prompt: withdraw it. The text stays in the body. |
| `panic` | Add hold `user`, withdraw everything, veil to 0 **instantly** (`seconds: 0`). |

`target` = the `windowKey` of the most recent STRONG evidence in the current block, else the current `windowKey`.
A learned session rule takes effect at once: the target window becomes ON, and later judgments for it are ignored.

---

## 3. State

### 3.1 Fields

| Field | Type | Meaning |
|---|---|---|
| `lastT` | Double | Last processed time |
| `session` | record? | null when no session. Holds `taskId`, `mode`, `durationSeconds`, `preset`, `shadow`, `reentryEnabled`, `sound`, `startedAt` |
| `holds` | ordered set of {reason, since, until?} | reasons: `user`, `meeting`, `sleep`, `idle`, `break`, `snooze`, `sensitive` |
| `askResumePending` | reason? | `idle`, `sleep` or `meeting` while an `AskResume` is open |
| `pausedAccum`, `pausedSince` | Double, Double? | Time in clock-stopping holds (`user`, `meeting`, `sleep`, `idle`, `break`) |
| `wrapUpSent` | Bool | Timed mode |
| `focus` | enum | `OnTask`, `Drifting`, `Confirmed`, `Persisting`, `Recovering` |
| `window` | {windowKey, siteKey, ruleLabel, since}? | Current foreground window; null at start and while sensitive |
| `block` | record? | The off-topic block, below |
| `frozen` | record? | A block that ended by return or sensitive window and may resume (4.5) |
| `returnPendingSince` | Double? | Arrival time of the ON evidence that started a return |
| `recoveringSince`, `confirmedAt` | Double? | |
| `lastEvidence` | {class, at}? | Most recent applied evidence in this block segment |
| `lastOnTaskWindowKey` | String? | Target for `BringBack` |
| `lastResumeAt` | Double | Session start or last resume; older observations are stale |
| `interruptOpen` | {kind, at}? | What the brain believes is on screen. Card and notice auto-expire at `at + 12` (the body fades them); a gate never auto-expires |
| `reentryOpen` | Bool | Pending next-step prompt |
| `interruptHistory` | [Double] | Times of every emitted `Interrupt`, for the rate cap |
| `sessionRules` | ordered map windowKey/siteKey → allow\|ignore | Learned this session |
| `cache` | ordered map windowKey → {kind: ON\|REFUSED, at} | Section 6.3 |
| `cadence` | {nextCheckAt, onStreak, neutralStreak, inFlight?: {id, at, windowKey}, nextRequestId} | Section 6.2 |
| `power` | {constrained, critical} | |
| `stats` | {offTopic, unsure, drifts, interrupts, refusals, nextBlockId} | For `Summary` |

`block` record: `id: Int?` (assigned when it first reaches Drifting), `onset`, `offAccum`, `runningSince?`,
`strongs: [(observedAt, contentKey)]`, `flagged: Bool`, `everFlagged: Bool`, `wasConfirmed: Bool`,
`interruptsInBlock: Int`, `interruptDueAt?`.

**Off-topic timer**: `timer(t) = offAccum + (runningSince == nil ? 0 : t - runningSince)`.
It is **cumulative per block** (PLAN 4.2): it pauses on return and continues on re-drift within 2 minutes.

### 3.2 States (PLAN 4.2) with exact conditions

| State | Enters when (exactly) | Leaves when |
|---|---|---|
| **No session** | start, or after end | `SessionStart` |
| **Paused** (Paused / Snoozed / Quiet / Break of PLAN 4.2) | any hold is active | the last hold is removed (resume) or the session ends |
| **OnTask** | session start; resume; Recovering done (S5); forgiveness (4.8). A **candidate** is OnTask with a block whose timer is below grace: nothing is visible | S6 grace reached |
| **Drifting** | S6: `timer(t) >= grace`. Sub-level by `flagged`: `false` = only NEUTRAL so far (shows "watching"), `true` = at least one STRONG since the segment began | S7, or return completes (S4), or hold, or forgiveness |
| **Confirmed** | S7 (section 4.4) on a block with `wasConfirmed = false` | S9 after 12 s; S4; hold; forgiveness |
| **Persisting** | S9, or S7 on a resumed block with `wasConfirmed = true` | S4; hold; forgiveness |
| **Recovering** | S4: ON evidence held for 15 s with no NEUTRAL or STRONG evidence in between | S5 after 5 s; NEUTRAL/STRONG evidence (treated as OnTask, see 4.3) |

`unsure` (NEUTRAL) can take the state to Drifting and no further. No path from NEUTRAL evidence reaches Confirmed, Persisting or any `Interrupt`.

### 3.3 Holds

| Hold | Added by | Clock | Block | Removed by | On removal |
|---|---|---|---|---|---|
| `user` | `pause`, `panic` | stops | closed | `resume` | resume |
| `break` | `break` | stops | closed | expiry (S1), `resume` | resume |
| `snooze` | `snooze` | runs | closed | expiry (S1), `resume` | resume |
| `meeting` | `MeetingStart` | stops | closed | `resume` only. `MeetingEnd` emits `AskResume{meeting}` | resume |
| `idle` | `Idle` | stops | closed | `Active`: if held < 300 s **ST**, remove and resume silently; else emit `AskResume{idle}` and wait for `resume` | resume |
| `sleep` | `Sleep` | stops | closed | `Wake`: same rule as idle with `AskResume{sleep}` | resume |
| `sensitive` | `SensitiveEntered` | runs | **frozen** (4.5, returnAt = entry time) | `SensitiveLeft` | window becomes null until the next `WindowChange` |

- **Closed** block: its timer value goes into `stats` (if it ever reached Drifting); a `frozen` block is also counted and cleared, so there is no 2-minute carry-over.
- Starting any hold: `cadence.nextCheckAt = ∞`, `inFlight = nil`, `returnPendingSince = nil`, focus = OnTask, withdraw open interrupt and re-entry prompt. Judgments that arrive while held are ignored (ON results still refresh the cache, except while `sensitive`).
- Idle is not backdated: the 120 s before `Idle` counts as active time. (Decision D15.)
- Beacon reason when several holds overlap, highest first: `user`, `meeting`, `sleep`, `idle`, `break`, `snooze`, `sensitive`.
- **resume**: focus = OnTask; `lastResumeAt = t`; if `window != nil`, evaluate it as on `WindowChange` (section 4.1) with request reason `resume`. With `window == nil` (after `SensitiveLeft`) nothing is requested until the next `WindowChange`.
- **end**: close the block (or count the frozen block), withdraw everything, emit `Summary`, set `session = nil`.

---

## 4. Evidence and transitions

### 4.1 WindowChange (not held)

1. Set `window = {windowKey, siteKey, ruleLabel, since: t}`; reset `onStreak` and `neutralStreak` to 0.
2. If a gate is open on a different `windowKey`, withdraw it.
3. First match wins, producing evidence at `observedAt = t`:
   session rule on windowKey or siteKey (ON, source rule) → `ruleLabel` (ON or STRONG, source rule) → cache ON (ON) → cache REFUSED (NEUTRAL, flag refusal, not recounted).
4. No match → one-shot `RequestJudgment{reason: window_change, urgency: now}`. Until it answers, the previous evidence stands.

### 4.2 Judgment

Discard (no state change) when: no session; held; `window == nil`; `windowKey != window.windowKey`; `observedAt < window.since`; `observedAt < lastResumeAt`;
`observedAt < lastEvidence.at` when that evidence came from a judgment; or a session rule matches the window (the rule wins).
Otherwise: clear `inFlight`; count a refusal or error in `stats.refusals` and write a REFUSED cache entry; write an ON cache entry for ON;
classify (2.2) and apply as evidence at `observedAt`.

### 4.3 Applying evidence (class `c`, observed at `o`, arrival `t`)

| Current | `c` = ON | `c` = NEUTRAL | `c` = STRONG |
|---|---|---|---|
| OnTask, no block | `lastOnTaskWindowKey = windowKey` | start block (4.5) | start block (4.5), `flagged = true`, `strongs = [(o, contentKey)]` |
| OnTask, candidate | discard the candidate (never counted) | add evidence | add to `strongs`, `flagged = true` |
| Drifting / Confirmed / Persisting, no return pending | start return: `returnPendingSince = t`, timer pauses at `t`, `strongs = []` | keep | append to `strongs`; `flagged = true` |
| same, return pending | keep | cancel return: timer resumes, `runningSince = max(o, returnPendingSince)` | cancel return as for NEUTRAL, then as STRONG above |
| Recovering | keep | focus = OnTask, then as "OnTask, no block" | same |

Always: `lastEvidence = {c, o}`. ON also sets `lastOnTaskWindowKey`.
Entering **Recovering** (S4): freeze the block into `frozen = {block, returnAt: returnPendingSince}`, `block = nil`, withdraw an open interrupt,
and if the block `wasConfirmed` and re-entry is enabled, open the re-entry prompt.

### 4.4 Confirmation: "two independent high-confidence verdicts" without a confidence number

S7 confirms when **all** hold:

1. Focus is Drifting, no return pending.
2. `timer(t) >= preset.confirmAfter`.
3. `strongs` holds an **independent pair**: two entries `a`, `b` with `b.observedAt - a.observedAt >= 10` when `contentKey`s differ, or `>= 20` when they are equal. **ST**
4. `lastEvidence.class == STRONG`.

Why this definition:
- **High confidence = `strong`.** Both framings agree (2.2). That is the only per-moment signal S1 found that removes false flags on genuinely on-task work (lenient precision 100% on dev and held-out).
- **Independence cannot mean independent model draws.** Decoding is greedy: the same input gives the same output, so asking twice about unchanged content adds nothing. What can come out differently is (a) **different content** (another video, another post, a scrolled feed), judged afresh, or (b) **the user is still there** after enough time to leave. Rule (a) needs 10 s so one burst of page loads does not count twice; rule (b) needs 20 s.
- `source: unchanged` (perceptual hash says nothing changed, verdict replayed) counts for (b): it proves the same content is still in front, which is the information a re-run would give.
- **What it does not fix.** S1's false flags were music players and personal messages: content a person can sit on for minutes. Time protects against glances, not against a persistent misjudgment. The protections for that are rules (A4 always-allowed apps, which should ship with music players in it), `that_was_fine`, and shadow mode for the first sessions. S1 also warns that the two framings' errors are correlated; the pair rule is weaker than it sounds.
- Condition 4 is the "unsure never advances past Drifting" rule applied at the moment of decision: a block whose latest evidence is NEUTRAL waits.

### 4.5 Blocks, candidates and the 2-minute rule

- **Start block** at evidence observed at `o`: if `frozen != nil` and `o - frozen.returnAt <= 120` **ST**, **resume** it: restore it as `block`, `runningSince = o`, `strongs = []`, `flagged = false` (then the evidence is applied, so STRONG sets it again). Otherwise count the frozen block into `stats` and start a new block: `onset = o`, `offAccum = 0`, `runningSince = o`, `id = nil`.
- The timer counts from `o`, the capture time of the first non-ON evidence, so it **includes grace and judge latency**. Grace and confirmation are measured on the same timer. A resumed block already has `timer >= grace`, so it re-enters Drifting at the first settle.
- A block gets its `id` (`stats.nextBlockId++`) when it first enters Drifting. A candidate that never reaches Drifting gets no id and is never counted.
- `stats` on close or end: if `everFlagged`, add the timer to `offTopic` and 1 to `drifts`; else (reached Drifting, never flagged) add to `unsure`.

### 4.6 Confirm effects

Not resumed (`wasConfirmed = false`): focus Confirmed, `confirmedAt = t`, `wasConfirmed = true`, `interruptDueAt = t`.
Resumed (`wasConfirmed = true`): focus Persisting, `interruptDueAt = max(t, lastInterruptAt + preset.repeat)`, or nil if the preset has no repeat. A quick look back at the task does not reset the escalation, and does not cause an immediate second nudge either.

### 4.7 Interrupts and the rate cap (L8)

S8 emits `Interrupt` when **all** hold: focus Confirmed or Persisting; no return pending; `interruptDueAt <= t`; `lastEvidence.class == STRONG`;
`interruptOpen == nil` (never stacked); the rate cap allows; the preset has an interrupt kind.

- **Rate cap ST**: at most 2 interrupts with time in `(t - 600, t]`. All kinds count (card, gate, notice). If blocked, `interruptDueAt = oldest time in that window + 600` (deferred, not dropped).
- If a gate is still open when a repeat falls due, skip it: `interruptDueAt += repeat`.
- After emitting: append `t` to `interruptHistory`, `interruptsInBlock++`, `stats.interrupts++`, `interruptDueAt = t + repeat` (nil if none).
- `severity` is 1 for the first interrupt of a block, 2 for repeats.
- **Shadow mode**: the same logic runs, but instead of `Interrupt` it emits `ShadowMark` (for the review queue, B15/B16), does not touch `interruptHistory` or `stats.interrupts`, and never opens a surface.

### 4.8 Forgiveness

`that_was_fine`, `mark_relevant`, `ignore_window`: discard the block and `frozen` (not counted in stats), focus OnTask, return pending cleared,
add the session rule (`allow` or `ignore`) and an ON cache entry for the target, withdraw interrupt and re-entry prompt, emit `LearnRule`.

---

## 5. Effects

### 5.1 Presentation (stateful effects, emitted only on change)

| Effect | Fields | Value as a function of state | Emitted when |
|---|---|---|---|
| `Beacon` | `state`, `reason?` | no session `off`; held `paused` + reason; shadow `resting`; OnTask `resting`; Drifting `watching` (not flagged) or `drifting` (flagged); Confirmed/Persisting `interrupted`; Recovering `recovering` | `(state, reason)` changes |
| `Veil` | `from`, `to`, `seconds` (integer percent) | target in 5.3 | the target `to` changes |
| `OffTopicTimer` | `seconds`, `running`, `visible` | `visible` = not shadow, not held, focus in {Drifting, Confirmed, Persisting}, `flagged`, `timer >= preset.timerVisibleFrom`. `running` = block timer running. `seconds = timer(t)` | `visible` changes, or `visible` stays true and `running` changes |
| `Clock` | `seconds`, `running` | Timed: remaining = `duration - active`; Open: active elapsed. `running` = no clock-stopping hold | session start, `running` changes, `extend`. Not on end |

`active(t) = t - startedAt - pausedAccum - (pausedSince == nil ? 0 : t - pausedSince)`.
The body animates the veil and counts the timer and clock itself between effects; the brain never emits per-second updates.

### 5.2 Effect order and one-shots

Within one event, effects appear in this order (at most one of each):

| # | Effect | Fields | Kind |
|---|---|---|---|
| 1 | `Withdraw` | `what: card\|gate\|notice\|reentry` | one-shot, when the brain closes a surface it believes is open (not on auto-expiry) |
| 2 | `Beacon` | see 5.1 | stateful |
| 3 | `Veil` | see 5.1 | stateful |
| 4 | `OffTopicTimer` | see 5.1 | stateful |
| 5 | `Clock` | see 5.1 | stateful |
| 6 | `Interrupt` | `kind: card\|gate\|notice`, `severity: 1\|2`, `block`, `windowKey` | one-shot (4.7) |
| 7 | `ReentryPrompt` | `block` | one-shot (4.3) |
| 8 | `WrapUp` | `remaining` | one-shot (S2) |
| 9 | `AskResume` | `reason: idle\|sleep\|meeting` | one-shot (3.3) |
| 10 | `ShadowMark` | `block`, `kind`, `windowKey` | one-shot (4.7) |
| 11 | `LearnRule` | `scope: session\|project`, `kind: allow\|ignore\|deny`, `keyType: window\|site`, `key` | one-shot (2.3) |
| 12 | `BringBack` | `windowKey?` | one-shot (2.3) |
| 13 | `RequestJudgment` | `id`, `reason: window_change\|resume\|cadence`, `urgency: now\|high\|normal`, `windowKey`, `allowVision` | one-shot (6.2) |
| 14 | `Cue` | `sound: soft` | one-shot, with `Interrupt` only when `session.sound` |
| 15 | `Summary` | `activeSeconds`, `offTopicSeconds`, `unsureSeconds`, `drifts`, `interrupts`, `refusals` | one-shot, at session end |

`Progress` (PLAN 7.1b) is derived by the stats module from `Summary` and is outside this state machine.
Interrupt never names the distraction; `windowKey` is there only so the body can place a gate over the right window.

### 5.3 Veil (color drain)

| Situation | Target `to` | `seconds` |
|---|---|---|
| no session, held, shadow, OnTask, Recovering, Drifting not flagged | 0 | 5 from any level (recovery is faster than drain); 0 for `panic` |
| Drifting, flagged | `preset.veilDrift` | `to - from` (drain 1 %/s **ST**) |
| Confirmed, Persisting | `preset.veilCap` | `to - from` |
| Return pending | current level (hold) | 0 |

Current level of the active segment `(from, to, startAt, seconds)` at `t`:
if `seconds == 0` or `t - startAt >= seconds` then `to`; else if `to >= from` then `from + floor((to - from) * (t - startAt) / seconds)`;
else `from - floor((from - to) * (t - startAt) / seconds)`. A new segment starts at the current level.
With drain at 1 %/s, reaching Standard's 60% takes 60 s and Strict's 80% takes 80 s, well above the 20 s minimum (D13). Nothing flashes.

---

## 6. Detection cadence, cache and power

### 6.1 Policy numbers per preset (all **ST**, from PLAN 4.3 unless noted)

| | Gentle (default) | Standard | Strict |
|---|---|---|---|
| `grace` (timer value to enter Drifting) | 45 | 25 | 10 |
| `timerVisibleFrom` | 60 | 0 | 0 |
| `veilDrift` / `veilCap` (%) | 0 / 0 (drain off) | 30 / 60 | 40 / 80 |
| `confirmAfter` (timer value) | 180 (one quiet notice at 3 min) | 75 | 45 |
| interrupt kind | `notice` | `card` | `gate` |
| `repeat` | none | 300 | 180 |
| re-entry prompt default | off | off (PLAN says "optional"; D12) | on |
| sound | off | off | off |

| Shared constant | Value **ST** | Source |
|---|---|---|
| Return hold before Recovering | 15 s | PLAN 4.1, 4.2 |
| Recovering duration and veil recovery | 5 s | PLAN 4.1 |
| Drain rate | 1 %/s | PLAN C3, D13 (at least 20 s) |
| Independent pair separation | 10 s (different content), 20 s (same) | this spec, 4.4 |
| Block resume window | 120 s | PLAN 4.2 |
| Card and notice auto-expiry | 12 s | PLAN 4.1 |
| Rate cap | 2 interrupts per rolling 600 s, never stacked | PLAN 4.8, L8 |
| Long idle or sleep before asking | 300 s | this spec (A11) |
| ON and REFUSED cache TTL | 900 s | this spec |
| Lost request timeout | 15 s | this spec |

Worked timing for a clear distraction that starts at 0 in Standard, with 3.5 s judgments: first STRONG observed at 0 (arrives 3.5);
checks every 10 s give observations at 14 and 28; the 0/28 pair is independent at 31.5; Drifting at 25 (timer, includes latency); nudge at 75.
That meets PLAN 9.3 (timer under 30 s, nudge under 75 s) only if the first verdict is STRONG. A first NEUTRAL verdict delays nothing visible
but delays the pair.

### 6.2 When the brain asks for a judgment

The brain owns cadence. Senses own the pipeline (stage 0 to 4) and the perceptual-hash skip.

| Trigger | `reason` | `urgency` |
|---|---|---|
| `WindowChange` with no rule or cache match | `window_change` | `now` |
| Resume from any hold, no rule or cache match | `resume` | `now` |
| `nextCheckAt <= t` (S10) | `cadence` | `high` if the block is flagged, else `normal` |

S10 fires only when: session running and not held; `window != nil`; `inFlight == nil` or `t - inFlight.at >= 15`; the window has no session rule,
no `ruleLabel = on_task`, no fresh REFUSED entry; `power.critical == false`. Window-change and resume requests ignore `inFlight` (they supersede it).
After a request, `nextCheckAt = ∞` until the answer arrives. `allowVision = !power.constrained`.

`nextCheckAt` is set when evidence is applied, to `t + interval`, first matching row:

| Situation after applying | Interval (s) **ST** |
|---|---|
| Focus Confirmed or Persisting, no return pending | 8 (owner, 2026-10-18: notice a slip fast; window changes are immediate) |
| Return pending | 4 |
| ON from a session rule or `ruleLabel` | none (deterministic, re-checked only on window change) |
| ON from cache | 20 (sets `onStreak = 3`) |
| ON from a judgment | `onStreak += 1`; 8, 12, then 20 for streak 1, 2, 3+ (adaptive backoff, PLAN 7.3) |
| STRONG, or block flagged | 4 (tightening under suspicion) |
| NEUTRAL, block not flagged | `neutralStreak += 1`; 5, 8, 12, then 20 for streak 1, 2, 3, 4+ |

`PowerChange{constrained}` doubles every interval; `critical` stops cadence requests entirely (rules and cache still work).
Pause on lock, sleep or display-off is the `sleep` hold (PLAN 9.1).

### 6.3 Cache

| Rule | Value |
|---|---|
| Key | `(taskId, windowKey)`. A session has one task, so state keys by `windowKey` |
| What is cached | ON verdicts (any source except rule), and REFUSED (a refusal or error) |
| Never cached | unsure, off_task weak or strong. Suspicion always needs fresh evidence |
| TTL | 900 s from the last ON judgment (a replayed `unchanged` ON refreshes it). Cache hits do not refresh |
| Size | 256 entries; evict the oldest `at`, ties by `windowKey` in byte order |
| Use | Only on `WindowChange` and resume. Cadence checks on the current window go to the senses, which skip the model when the perceptual hash is unchanged and answer `source: unchanged` |
| Refusals | One refusal per window per 15 minutes. Then the window counts NEUTRAL from cache, with no requests |

**Never judging sensitive windows** is structural: the senses send `SensitiveEntered` with no keys, the brain holds, sets `window = nil`
and `inFlight = nil`, and S10 requires a window. A judgment arriving during the hold is discarded and not cached.

### 6.4 Judgments per hour (estimate, not measured)

One "judgment" = both framings (two model calls), about 3.5 s wall time.

| Focused hour | Count | Assumption |
|---|---|---|
| Window changes to uncached windows | 10 | 30 switches, a third to new pages or documents |
| Cadence checks | about 45 | about 90 s apart while stable, plus early 30/60 s checks after the 10 new windows |
| of which reach the model | about 22 | half find a changed screen (typing, scrolling); the rest are `unchanged` |
| **Model judgments** | **about 32** | about 1 every 2 minutes; about 112 s of inference, 3% duty |

| Drifting hour | Count | Assumption |
|---|---|---|
| Focused 45 minutes | about 24 | as above, scaled |
| 3 confirmed blocks of about 5 minutes | about 48 | per block: 1 window change, about 7 checks at 10 s before confirm, about 8 at 30 s after; feeds and video rarely hash as unchanged |
| 10 minutes of NEUTRAL (music, messages) | about 12 | backoff 10, 20, 40, 60 s |
| **Model judgments** | **about 84** | about 294 s of inference, 8% duty |

Energy per judgment on the system model is still unmeasured (S1: needs `powermetrics`). These counts are what to multiply it by.

---

## 7. Decisions I made

PLAN is silent or ambiguous on these. Each lists the rejected alternative.

| # | Decision | Rejected alternative, and why |
|---|---|---|
| D1 | `strong = false` off_task is NEUTRAL | Count weak off as half a strong: re-introduces the single-judge 50% precision |
| D2 | Independence = different content 10 s apart, or same content 20 s apart (4.4) | Different content only: a static video never confirms. N consecutive strongs: greedy decoding makes repeats free |
| D3 | Drifting without any STRONG shows only the "watching" ring: no drain, no timer | PLAN's literal reading (drain on any non-on-task): music and messages would drain the screen |
| D4 | Off-topic timer counts from the capture time of the first non-ON evidence, including grace and latency; grace and confirm use the same timer | Timer from drift start: under-reports and makes "cumulative" ambiguous |
| D5 | Return: timer pauses at arrival of ON, veil holds, nothing else changes for 15 s | Instant recovery: a stray on_task verdict would flicker everything |
| D6 | A candidate (below grace) is discarded on ON and never counted | Carry candidates under the 2-minute rule: invisible state with surprising effects |
| D7 | A resumed, already-confirmed block goes to Persisting on the repeat schedule | Fresh nudge on re-confirm: feels like nagging right after a glance back |
| D8 | Holds close the block; only `sensitive` freezes it (2-minute rule from entry) | Freeze for all holds: a break is a real return, not a dodge |
| D9 | Snooze and sensitive keep the session clock running; pause, break, meeting, idle and sleep stop it | Snooze stops the clock: snoozing usually means "I'm working, stop judging" |
| D10 | No judging during snooze | Judge for stats: power cost with no user benefit |
| D11 | Veil in integer percent; Drifting target is half the cap | Continuous floats: harder to keep identical across languages |
| D12 | Standard re-entry prompt off by default | On by default: PLAN says "optional"; calm rules favor off |
| D13 | Rate cap counts all kinds, uses `(t-600, t]`, and defers rather than drops | Drop capped interrupts: a real distraction would go silent for a whole repeat period |
| D14 | Every interrupt, including repeats, needs latest evidence STRONG | Repeat on schedule regardless: would interrupt on unsure |
| D15 | Idle is not backdated | Backdate by 120 s: retroactive edits to timers already shown |
| D16 | `that_was_fine` teaches a windowKey rule, `mark_relevant` a siteKey rule, both project-scoped; `ignore_window` is session-only | One rule kind for all: "this video was fine" would allow all of YouTube |
| D17 | Shadow mode keeps the ring at resting and emits `ShadowMark` | Show the ring changes in shadow: still a signal the user did not ask for |
| D18 | `Beacon(interrupted)` means "confirmed", even while a capped interrupt waits | Separate state for "confirmed, waiting": more states, no user value |
| D19 | `back_to_task` is not evidence; the next `WindowChange` is | Treat the click as ON: the user may not actually go back |
| D20 | `WindowChange` only on `windowKey` change; content digests travel in judgments | WindowChange per content change: scrolling would flood requests and make in-flight answers stale |
| D21 | Added `Beacon(off)`, `Withdraw`, `Clock`, `WrapUp`, `AskResume`, `LearnRule`, `BringBack`, `ShadowMark`, `Summary`, `RequestJudgment` to PLAN 7.1b's list | Leave them to the body: behavior would differ between OSs |

---

## 8. Open questions for the owner

1. **Is Standard allowed to nudge outside shadow mode before we can measure false nudges per 3 hours?** Per-moment precision is 71-79% and the episode-level rate is unknown until the episode simulator exists (S1 recommendation 3). My suggestion: shadow mode until that number is measured, then decide.
2. **Should "watching" (dashed ring for unsure-only drift) show at all?** It is honest, but it is a visible reaction to something ambiguous. The alternative is to show nothing until a STRONG verdict.
3. **Should music players and messaging apps ship in the default always-allowed list?** They were S1's false nudges. Allowing them by default trades some missed distractions for fewer false ones.
4. **How many sessions does shadow mode last** (B15 "first few sessions")? This spec takes it as a session flag; the count is a product choice.

---

## 9. Golden traces

### 9.1 Format

One JSON object per trace. The runner expands it into an event list, feeds the brain, and compares the effects of every event.

| Field | Meaning |
|---|---|
| `trace` | Name |
| `ticks` | `{"from": 0, "until": N}`: synthetic `Tick` at every integer second in `[from, until]` |
| `ignore` | Effect types left out of comparison (most traces ignore `RequestJudgment`; T01, T07, T14 test it) |
| `prelude` | Optional. Expands to three steps: `SessionStart` (the given fields) at 0 with fx `Beacon resting` and `Clock{seconds: duration or 0, running: true}`; `WindowChange{windowKey: "w:editor"}` at 0 with no fx; `Judgment{observedAt: 0, windowKey: "w:editor", contentKey: "c:e1", label: "on_task"}` at 3.5 with no fx |
| `steps` | `{"t", "ev", "fx"}`. `ev` is an event (externally tagged) or the string `"Tick"`, which asserts the effects of that synthetic tick instead of adding an event |
| `repeat` | On a step: `{"every": s, "until": u}` adds copies at `t + k*s <= u`, with `observedAt` shifted by the same amount. Copies expect `fx: []` |

Merge order at equal `t`: explicit events in file order, then the tick. Any event without a step expects `[]`.
Field defaults: `SessionStart` `sessionId "s"`, `taskId "task"`, `mode "Open"`, `preset "Standard"`, `shadow false`, `reentryPrompt null`, `sound false`;
`Judgment` `requestId null`, `strong false`, `source "model"`, `flag "none"`; `WindowChange` `siteKey = windowKey`, `ruleLabel null`;
`RequestJudgment` `allowVision true`; `Beacon` `reason null`. Effects shown here as `{"Type": {fields}}`.

Short names in these traces: STRONG judgment = `"label":"off_task","strong":true`.

### T01 Quiet on-task (Standard): backoff, cache, nothing visible

Checks at 8, 12, 20 s after on-task verdicts (owner, 2026-10-18: faster than the old 30/60/90); a cache hit on return to the editor skips the judge and sets the stable 20 s interval.

```json
{"trace":"T01-quiet-on-task","ticks":{"from":0,"until":180},"ignore":[],"steps":[
{"t":0,"ev":{"SessionStart":{"preset":"Standard"}},"fx":[{"Beacon":{"state":"resting"}},{"Clock":{"seconds":0,"running":true}}]},
{"t":0,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[{"RequestJudgment":{"id":1,"reason":"window_change","urgency":"now","windowKey":"w:editor"}}]},
{"t":3.5,"ev":{"Judgment":{"requestId":1,"observedAt":0,"windowKey":"w:editor","contentKey":"c:e1","label":"on_task"}},"fx":[]},
{"t":12,"ev":"Tick","fx":[{"RequestJudgment":{"id":2,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":15.5,"ev":{"Judgment":{"requestId":2,"observedAt":12,"windowKey":"w:editor","contentKey":"c:e1","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":28,"ev":"Tick","fx":[{"RequestJudgment":{"id":3,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":31.5,"ev":{"Judgment":{"requestId":3,"observedAt":28,"windowKey":"w:editor","contentKey":"c:e2","label":"on_task"}},"fx":[]},
{"t":52,"ev":"Tick","fx":[{"RequestJudgment":{"id":4,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":55.5,"ev":{"Judgment":{"requestId":4,"observedAt":52,"windowKey":"w:editor","contentKey":"c:e2","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":76,"ev":"Tick","fx":[{"RequestJudgment":{"id":5,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":79.5,"ev":{"Judgment":{"requestId":5,"observedAt":76,"windowKey":"w:editor","contentKey":"c:e2","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":100,"ev":"Tick","fx":[{"RequestJudgment":{"id":6,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":103.5,"ev":{"Judgment":{"requestId":6,"observedAt":100,"windowKey":"w:editor","contentKey":"c:e2","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":120,"ev":{"WindowChange":{"windowKey":"w:docs"}},"fx":[{"RequestJudgment":{"id":7,"reason":"window_change","urgency":"now","windowKey":"w:docs"}}]},
{"t":123.5,"ev":{"Judgment":{"requestId":7,"observedAt":120,"windowKey":"w:docs","contentKey":"c:d1","label":"on_task"}},"fx":[]},
{"t":132,"ev":"Tick","fx":[{"RequestJudgment":{"id":8,"reason":"cadence","urgency":"normal","windowKey":"w:docs"}}]},
{"t":135.5,"ev":{"Judgment":{"requestId":8,"observedAt":132,"windowKey":"w:docs","contentKey":"c:d1","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":145,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[]},
{"t":165,"ev":"Tick","fx":[{"RequestJudgment":{"id":9,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":168.5,"ev":{"Judgment":{"requestId":9,"observedAt":165,"windowKey":"w:editor","contentKey":"c:e2","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":180,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":180,"offTopicSeconds":0,"unsureSeconds":0,"drifts":0,"interrupts":0,"refusals":0}}]}
]}
```
Check: 3.5+8=11.5→tick 12; 15.5+12=27.5→28; 31.5+20=51.5→52; then every 20 s (76, 100); 123.5+8=131.5→tick 132 after the docs verdict; the cache hit at 145 sets the 20 s interval, so 165.

### T02 Short drift that recovers before confirmation (Standard)

```json
{"trace":"T02-short-drift","ticks":{"from":0,"until":200},"ignore":["RequestJudgment"],"prelude":{"preset":"Standard"},"steps":[
{"t":100,"ev":{"WindowChange":{"windowKey":"w:yt"}},"fx":[]},
{"t":103.5,"ev":{"Judgment":{"observedAt":100,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"repeat":{"every":14,"until":131.5},"fx":[]},
{"t":125,"ev":"Tick","fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":30,"seconds":30}},{"OffTopicTimer":{"seconds":25,"running":true,"visible":true}}]},
{"t":140,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[{"Veil":{"from":15,"to":15,"seconds":0}},{"OffTopicTimer":{"seconds":40,"running":false,"visible":true}}]},
{"t":155,"ev":"Tick","fx":[{"Beacon":{"state":"recovering"}},{"Veil":{"from":15,"to":0,"seconds":5}},{"OffTopicTimer":{"seconds":40,"running":false,"visible":false}}]},
{"t":160,"ev":"Tick","fx":[{"Beacon":{"state":"resting"}}]},
{"t":200,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":200,"offTopicSeconds":40,"unsureSeconds":0,"drifts":1,"interrupts":0,"refusals":0}}]}
]}
```
Check: onset 100, grace 25 → 125. Pair 100/128 at 131.5, but timer 31.5 < 75. At 140 the editor is a cache hit (cached 3.5, age 136.5 < 900): ON, return pending, timer 140-100 = 40, veil at 140 = floor(30*15/30) = 15. 140+15 = 155 → Recovering; 160 → resting.

### T03 Confirmed distraction in Standard: nudge, ignored, repeat, rate cap

```json
{"trace":"T03-standard-nudge-repeat-cap","ticks":{"from":0,"until":760},"ignore":["RequestJudgment"],"prelude":{"preset":"Standard"},"steps":[
{"t":60,"ev":{"WindowChange":{"windowKey":"w:yt"}},"fx":[]},
{"t":63.5,"ev":{"Judgment":{"observedAt":60,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"repeat":{"every":14,"until":133.5},"fx":[]},
{"t":85,"ev":"Tick","fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":30,"seconds":30}},{"OffTopicTimer":{"seconds":25,"running":true,"visible":true}}]},
{"t":135,"ev":"Tick","fx":[{"Beacon":{"state":"interrupted"}},{"Veil":{"from":30,"to":60,"seconds":30}},{"Interrupt":{"kind":"card","severity":1,"block":1,"windowKey":"w:yt"}}]},
{"t":163.5,"ev":{"Judgment":{"observedAt":160,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"repeat":{"every":30,"until":433.5},"fx":[]},
{"t":435,"ev":"Tick","fx":[{"Interrupt":{"kind":"card","severity":2,"block":1,"windowKey":"w:yt"}}]},
{"t":450,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[{"OffTopicTimer":{"seconds":390,"running":false,"visible":true}}]},
{"t":465,"ev":"Tick","fx":[{"Beacon":{"state":"recovering"}},{"Veil":{"from":60,"to":0,"seconds":5}},{"OffTopicTimer":{"seconds":390,"running":false,"visible":false}}]},
{"t":470,"ev":"Tick","fx":[{"Beacon":{"state":"resting"}}]},
{"t":600,"ev":{"WindowChange":{"windowKey":"w:reddit"}},"fx":[]},
{"t":603.5,"ev":{"Judgment":{"observedAt":600,"windowKey":"w:reddit","contentKey":"c:r1","label":"off_task","strong":true}},"repeat":{"every":14,"until":673.5},"fx":[]},
{"t":625,"ev":"Tick","fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":30,"seconds":30}},{"OffTopicTimer":{"seconds":25,"running":true,"visible":true}}]},
{"t":675,"ev":"Tick","fx":[{"Beacon":{"state":"interrupted"}},{"Veil":{"from":30,"to":60,"seconds":30}}]},
{"t":687.5,"ev":{"Judgment":{"observedAt":684,"windowKey":"w:reddit","contentKey":"c:r1","label":"off_task","strong":true}},"repeat":{"every":34,"until":721.5},"fx":[]},
{"t":735,"ev":"Tick","fx":[{"Interrupt":{"kind":"card","severity":1,"block":2,"windowKey":"w:reddit"}}]},
{"t":760,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Veil":{"from":60,"to":0,"seconds":5}},{"OffTopicTimer":{"seconds":160,"running":false,"visible":false}},{"Summary":{"activeSeconds":760,"offTopicSeconds":550,"unsureSeconds":0,"drifts":2,"interrupts":3,"refusals":0}}]}
]}
```
Check: block 1 onset 60; Drifting 85; pair 60/88; timer 75 at 135, last evidence STRONG (133.5) → card. The user ignores it (it fades at 147, no effect). Repeat due 135+300 = 435; cap window (-165, 435] holds {135} → allowed. At 450 the editor (cache age 446.5) gives ON: timer 450-60 = 390; veil already at its target 60, so the hold changes nothing. Recovering 465, resting 470. Re-drift at 600: 600-450 = 150 > 120, so a **new** block 2. Confirm at 675, but (75, 675] holds {135, 435}: capped, deferred to 135+600 = 735. At 735, (135, 735] holds {435} → allowed; latest evidence 721.5 is STRONG; severity 1 (first in block 2). End: block 2 timer 760-600 = 160; total 390+160 = 550.

### T04 Strict gate, back to task, re-entry prompt

```json
{"trace":"T04-strict-gate","ticks":{"from":0,"until":150},"ignore":["RequestJudgment"],"prelude":{"preset":"Strict"},"steps":[
{"t":50,"ev":{"WindowChange":{"windowKey":"w:yt"}},"fx":[]},
{"t":53.5,"ev":{"Judgment":{"observedAt":50,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"repeat":{"every":14,"until":81.5},"fx":[]},
{"t":60,"ev":"Tick","fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":40,"seconds":40}},{"OffTopicTimer":{"seconds":10,"running":true,"visible":true}}]},
{"t":95,"ev":"Tick","fx":[{"Beacon":{"state":"interrupted"}},{"Veil":{"from":35,"to":80,"seconds":45}},{"Interrupt":{"kind":"gate","severity":1,"block":1,"windowKey":"w:yt"}}]},
{"t":101,"ev":{"UserAction":{"action":"back_to_task"}},"fx":[{"Withdraw":{"what":"gate"}},{"BringBack":{"windowKey":"w:editor"}}]},
{"t":101.5,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[{"Veil":{"from":41,"to":41,"seconds":0}},{"OffTopicTimer":{"seconds":51.5,"running":false,"visible":true}}]},
{"t":117,"ev":"Tick","fx":[{"Beacon":{"state":"recovering"}},{"Veil":{"from":41,"to":0,"seconds":5}},{"OffTopicTimer":{"seconds":51.5,"running":false,"visible":false}},{"ReentryPrompt":{"block":1}}]},
{"t":122,"ev":"Tick","fx":[{"Beacon":{"state":"resting"}}]},
{"t":130,"ev":{"UserAction":{"action":"next_step"}},"fx":[{"Withdraw":{"what":"reentry"}}]},
{"t":150,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":150,"offTopicSeconds":51.5,"unsureSeconds":0,"drifts":1,"interrupts":1,"refusals":0}}]}
]}
```
Check: grace 10 → 60. Pair 50/78 at 81.5. Timer 45 at 95; veil at 95 = floor(40*35/40) = 35. Veil at 101.5 = 35 + floor(45*6.5/45) = 35+6 = 41. Return pending from 101.5; 116.5 → tick 117. Re-entry is on in Strict and the block was confirmed.

### T05 Gentle: quiet notice at 3 minutes, no drain

```json
{"trace":"T05-gentle-notice","ticks":{"from":0,"until":330},"ignore":["RequestJudgment"],"prelude":{"preset":"Gentle"},"steps":[
{"t":100,"ev":{"WindowChange":{"windowKey":"w:yt"}},"fx":[]},
{"t":103.5,"ev":{"Judgment":{"observedAt":100,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"repeat":{"every":14,"until":271.5},"fx":[]},
{"t":145,"ev":"Tick","fx":[{"Beacon":{"state":"drifting"}}]},
{"t":160,"ev":"Tick","fx":[{"OffTopicTimer":{"seconds":60,"running":true,"visible":true}}]},
{"t":280,"ev":"Tick","fx":[{"Beacon":{"state":"interrupted"}},{"Interrupt":{"kind":"notice","severity":1,"block":1,"windowKey":"w:yt"}}]},
{"t":300,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[{"OffTopicTimer":{"seconds":200,"running":false,"visible":true}}]},
{"t":315,"ev":"Tick","fx":[{"Beacon":{"state":"recovering"}},{"OffTopicTimer":{"seconds":200,"running":false,"visible":false}}]},
{"t":320,"ev":"Tick","fx":[{"Beacon":{"state":"resting"}}]},
{"t":330,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":330,"offTopicSeconds":200,"unsureSeconds":0,"drifts":1,"interrupts":1,"refusals":0}}]}
]}
```
Check: grace 45 → 145; timer visible from 60 → 160; confirm 180 → 280 (last STRONG at 271.5). Veil target is always 0 in Gentle, so no `Veil` effects. No repeat, no re-entry.

### T06 Unsure flood never nudges (Standard)

A music player judged unsure for five minutes, with one weak off_task (two framings disagreed).

```json
{"trace":"T06-unsure-flood","ticks":{"from":0,"until":430},"ignore":["RequestJudgment"],"prelude":{"preset":"Standard"},"steps":[
{"t":100,"ev":{"WindowChange":{"windowKey":"w:music"}},"fx":[]},
{"t":103.5,"ev":{"Judgment":{"observedAt":100,"windowKey":"w:music","contentKey":"c:m1","label":"unsure"}},"fx":[]},
{"t":117.5,"ev":{"Judgment":{"observedAt":114,"windowKey":"w:music","contentKey":"c:m1","label":"unsure"}},"fx":[]},
{"t":125,"ev":"Tick","fx":[{"Beacon":{"state":"watching"}}]},
{"t":141.5,"ev":{"Judgment":{"observedAt":138,"windowKey":"w:music","contentKey":"c:m2","label":"unsure"}},"fx":[]},
{"t":185.5,"ev":{"Judgment":{"observedAt":182,"windowKey":"w:music","contentKey":"c:m3","label":"off_task","strong":false}},"fx":[]},
{"t":249.5,"ev":{"Judgment":{"observedAt":246,"windowKey":"w:music","contentKey":"c:m3","label":"unsure"}},"repeat":{"every":64,"until":377.5},"fx":[]},
{"t":400,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[]},
{"t":415,"ev":"Tick","fx":[{"Beacon":{"state":"recovering"}}]},
{"t":420,"ev":"Tick","fx":[{"Beacon":{"state":"resting"}}]},
{"t":430,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":430,"offTopicSeconds":0,"unsureSeconds":300,"drifts":0,"interrupts":0,"refusals":0}}]}
]}
```
Check: arrival times follow the NEUTRAL backoff 10, 20, 40, 60 (103.5→114, 117.5→138, 141.5→182, 185.5→246, then every 64 = 60 + 3.5 + rounding to the tick). Drifting (not flagged) at 125 shows only "watching". No veil, no timer, no interrupt. Block value 400-100 = 300 goes to `unsureSeconds`.

### T07 Judge refusal (Standard): unsure plus flag, cached, no retries

```json
{"trace":"T07-refusal","ticks":{"from":0,"until":260},"ignore":[],"steps":[
{"t":0,"ev":{"SessionStart":{"preset":"Standard"}},"fx":[{"Beacon":{"state":"resting"}},{"Clock":{"seconds":0,"running":true}}]},
{"t":0,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[{"RequestJudgment":{"id":1,"reason":"window_change","urgency":"now","windowKey":"w:editor"}}]},
{"t":3.5,"ev":{"Judgment":{"requestId":1,"observedAt":0,"windowKey":"w:editor","contentKey":"c:e1","label":"on_task"}},"fx":[]},
{"t":12,"ev":"Tick","fx":[{"RequestJudgment":{"id":2,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":15.5,"ev":{"Judgment":{"requestId":2,"observedAt":12,"windowKey":"w:editor","contentKey":"c:e1","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":28,"ev":"Tick","fx":[{"RequestJudgment":{"id":3,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":31.5,"ev":{"Judgment":{"requestId":3,"observedAt":28,"windowKey":"w:editor","contentKey":"c:e1","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":52,"ev":"Tick","fx":[{"RequestJudgment":{"id":4,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":55.5,"ev":{"Judgment":{"requestId":4,"observedAt":52,"windowKey":"w:editor","contentKey":"c:e1","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":76,"ev":"Tick","fx":[{"RequestJudgment":{"id":5,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":79.5,"ev":{"Judgment":{"requestId":5,"observedAt":76,"windowKey":"w:editor","contentKey":"c:e1","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":90,"ev":{"WindowChange":{"windowKey":"w:msg"}},"fx":[{"RequestJudgment":{"id":6,"reason":"window_change","urgency":"now","windowKey":"w:msg"}}]},
{"t":93.5,"ev":{"Judgment":{"requestId":6,"observedAt":90,"windowKey":"w:msg","contentKey":"c:msg1","label":"off_task","strong":true,"flag":"refusal"}},"fx":[]},
{"t":115,"ev":"Tick","fx":[{"Beacon":{"state":"watching"}}]},
{"t":160,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[]},
{"t":164,"ev":"Tick","fx":[{"RequestJudgment":{"id":7,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":167.5,"ev":{"Judgment":{"requestId":7,"observedAt":164,"windowKey":"w:editor","contentKey":"c:e1","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":172,"ev":"Tick","fx":[{"RequestJudgment":{"id":8,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":175,"ev":"Tick","fx":[{"Beacon":{"state":"recovering"}}]},
{"t":175.5,"ev":{"Judgment":{"requestId":8,"observedAt":172,"windowKey":"w:editor","contentKey":"c:e1","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":180,"ev":"Tick","fx":[{"Beacon":{"state":"resting"}}]},
{"t":196,"ev":"Tick","fx":[{"RequestJudgment":{"id":9,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":199,"ev":{"Judgment":{"requestId":9,"observedAt":196,"windowKey":"w:editor","contentKey":"c:e1","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":200,"ev":{"WindowChange":{"windowKey":"w:msg"}},"fx":[{"Beacon":{"state":"watching"}}]},
{"t":260,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":260,"offTopicSeconds":0,"unsureSeconds":130,"drifts":0,"interrupts":0,"refusals":1}}]}
]}
```
Check: the refusal's `off_task, strong` is ignored (flag wins) → NEUTRAL, REFUSED cached, no cadence on `w:msg`. Request 3 is superseded and never answered. At 160 the editor is a cache hit (refreshed at 37.5): return pending, cadence 10 → 170; at 173.5 still pending → 183.5 → tick 184; at 187.5 focus OnTask, `onStreak` 3 (cache hit) + 1 = 4 → 90 → 277.5 > 260. At 200 `w:msg` hits the REFUSED cache: NEUTRAL at 200, no request. 200-160 = 40 ≤ 120, so block resumes at value 160-100 = 60 ≥ 25: straight to Drifting, not flagged. End: 60 + (260-200) = 120 unsure seconds; one refusal counted.

### T08 Idle and resume (Standard): short idle auto-resumes, long idle asks

```json
{"trace":"T08-idle","ticks":{"from":0,"until":1100},"ignore":["RequestJudgment"],"prelude":{"preset":"Standard"},"steps":[
{"t":100,"ev":{"WindowChange":{"windowKey":"w:reddit"}},"fx":[]},
{"t":103.5,"ev":{"Judgment":{"observedAt":100,"windowKey":"w:reddit","contentKey":"c:r1","label":"off_task","strong":true}},"repeat":{"every":14,"until":159.5},"fx":[]},
{"t":125,"ev":"Tick","fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":30,"seconds":30}},{"OffTopicTimer":{"seconds":25,"running":true,"visible":true}}]},
{"t":160,"ev":{"Idle":{}},"fx":[{"Beacon":{"state":"paused","reason":"idle"}},{"Veil":{"from":30,"to":0,"seconds":5}},{"OffTopicTimer":{"seconds":60,"running":false,"visible":false}},{"Clock":{"seconds":160,"running":false}}]},
{"t":220,"ev":{"Active":{}},"fx":[{"Beacon":{"state":"resting"}},{"Clock":{"seconds":160,"running":true}}]},
{"t":221,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[]},
{"t":400,"ev":{"Idle":{}},"fx":[{"Beacon":{"state":"paused","reason":"idle"}},{"Clock":{"seconds":340,"running":false}}]},
{"t":1000,"ev":{"Active":{}},"fx":[{"AskResume":{"reason":"idle"}}]},
{"t":1010,"ev":{"UserAction":{"action":"resume"}},"fx":[{"Beacon":{"state":"resting"}},{"Clock":{"seconds":340,"running":true}}]},
{"t":1100,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":430,"offTopicSeconds":60,"unsureSeconds":0,"drifts":1,"interrupts":0,"refusals":0}}]}
]}
```
Check: Idle at 160 closes the block (timer 60, flagged → counted). Veil at 160 = 30 (ramp ended at 155). Idle 60 s < 300 → silent resume. Second idle 600 s ≥ 300 → ask. Paused 160-220 (60) and 400-1010 (610): active = 1100-670 = 430; clock at 400 = 400-60 = 340.

### T09 Meeting auto-pause in a Timed session, extend, wrap-up, timer end

```json
{"trace":"T09-meeting-timed","ticks":{"from":0,"until":5110},"ignore":["RequestJudgment"],"prelude":{"preset":"Standard","mode":"Timed","durationSeconds":3000},"steps":[
{"t":600,"ev":{"MeetingStart":{}},"fx":[{"Beacon":{"state":"paused","reason":"meeting"}},{"Clock":{"seconds":2400,"running":false}}]},
{"t":2400,"ev":{"MeetingEnd":{}},"fx":[{"AskResume":{"reason":"meeting"}}]},
{"t":2410,"ev":{"UserAction":{"action":"resume"}},"fx":[{"Beacon":{"state":"resting"}},{"Clock":{"seconds":2400,"running":true}}]},
{"t":4690,"ev":"Tick","fx":[{"WrapUp":{"remaining":120}}]},
{"t":4700,"ev":{"UserAction":{"action":"extend","minutes":5}},"fx":[{"Clock":{"seconds":410,"running":true}}]},
{"t":4990,"ev":"Tick","fx":[{"WrapUp":{"remaining":120}}]},
{"t":5110,"ev":"Tick","fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":3300,"offTopicSeconds":0,"unsureSeconds":0,"drifts":0,"interrupts":0,"refusals":0}}]}
]}
```
Check: active after resume = 600 + (t-2410). Wrap-up when remaining ≤ 120: 600 + (t-2410) = 2880 → t = 4690. Extend at 4700: active 2890, duration 3300, remaining 410. Second wrap-up at active 3180 → t = 4990. End at active 3300 → t = 5110.

### T10 Break from the nudge card (Standard)

```json
{"trace":"T10-break","ticks":{"from":0,"until":600},"ignore":["RequestJudgment"],"prelude":{"preset":"Standard"},"steps":[
{"t":100,"ev":{"WindowChange":{"windowKey":"w:yt"}},"fx":[]},
{"t":103.5,"ev":{"Judgment":{"observedAt":100,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"repeat":{"every":14,"until":173.5},"fx":[]},
{"t":125,"ev":"Tick","fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":30,"seconds":30}},{"OffTopicTimer":{"seconds":25,"running":true,"visible":true}}]},
{"t":175,"ev":"Tick","fx":[{"Beacon":{"state":"interrupted"}},{"Veil":{"from":30,"to":60,"seconds":30}},{"Interrupt":{"kind":"card","severity":1,"block":1,"windowKey":"w:yt"}}]},
{"t":180,"ev":{"UserAction":{"action":"break","minutes":5}},"fx":[{"Withdraw":{"what":"card"}},{"Beacon":{"state":"paused","reason":"break"}},{"Veil":{"from":35,"to":0,"seconds":5}},{"OffTopicTimer":{"seconds":80,"running":false,"visible":false}},{"Clock":{"seconds":180,"running":false}}]},
{"t":470,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[]},
{"t":480,"ev":"Tick","fx":[{"Beacon":{"state":"resting"}},{"Clock":{"seconds":180,"running":true}}]},
{"t":600,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":300,"offTopicSeconds":80,"unsureSeconds":0,"drifts":1,"interrupts":1,"refusals":0}}]}
]}
```
Check: veil at 180 = 30 + floor(30*5/30) = 35. Card open 175-187, so it is withdrawn. The window change during the break is recorded only. Break ends 180+300 = 480; editor cached (age 476.5) → ON, no request. Active = 600-300 = 300.

### T11 Snooze during drift (Standard)

```json
{"trace":"T11-snooze","ticks":{"from":0,"until":1040},"ignore":["RequestJudgment"],"prelude":{"preset":"Standard"},"steps":[
{"t":100,"ev":{"WindowChange":{"windowKey":"w:yt"}},"fx":[]},
{"t":103.5,"ev":{"Judgment":{"observedAt":100,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"repeat":{"every":14,"until":131.5},"fx":[]},
{"t":125,"ev":"Tick","fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":30,"seconds":30}},{"OffTopicTimer":{"seconds":25,"running":true,"visible":true}}]},
{"t":130,"ev":{"UserAction":{"action":"snooze","minutes":15}},"fx":[{"Beacon":{"state":"paused","reason":"snooze"}},{"Veil":{"from":5,"to":0,"seconds":5}},{"OffTopicTimer":{"seconds":30,"running":false,"visible":false}}]},
{"t":1030,"ev":"Tick","fx":[{"Beacon":{"state":"resting"}}]},
{"t":1033.5,"ev":{"Judgment":{"observedAt":1030,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"fx":[]},
{"t":1040,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":1040,"offTopicSeconds":30,"unsureSeconds":0,"drifts":1,"interrupts":0,"refusals":0}}]}
]}
```
Check: snooze keeps the clock running (no `Clock` effect). The 131.5 judgment arrives during the hold and is ignored. Snooze ends 130+900 = 1030. The new candidate (onset 1030, timer 10 < 25 at end) is discarded.

### T12 Panic while the Strict gate is up

```json
{"trace":"T12-panic","ticks":{"from":0,"until":210},"ignore":["RequestJudgment"],"prelude":{"preset":"Strict"},"steps":[
{"t":50,"ev":{"WindowChange":{"windowKey":"w:yt"}},"fx":[]},
{"t":53.5,"ev":{"Judgment":{"observedAt":50,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"repeat":{"every":14,"until":81.5},"fx":[]},
{"t":60,"ev":"Tick","fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":40,"seconds":40}},{"OffTopicTimer":{"seconds":10,"running":true,"visible":true}}]},
{"t":95,"ev":"Tick","fx":[{"Beacon":{"state":"interrupted"}},{"Veil":{"from":35,"to":80,"seconds":45}},{"Interrupt":{"kind":"gate","severity":1,"block":1,"windowKey":"w:yt"}}]},
{"t":97,"ev":{"UserAction":{"action":"panic"}},"fx":[{"Withdraw":{"what":"gate"}},{"Beacon":{"state":"paused","reason":"user"}},{"Veil":{"from":37,"to":0,"seconds":0}},{"OffTopicTimer":{"seconds":47,"running":false,"visible":false}},{"Clock":{"seconds":97,"running":false}}]},
{"t":200,"ev":{"UserAction":{"action":"resume"}},"fx":[{"Beacon":{"state":"resting"}},{"Clock":{"seconds":97,"running":true}}]},
{"t":210,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":107,"offTopicSeconds":47,"unsureSeconds":0,"drifts":1,"interrupts":1,"refusals":0}}]}
]}
```
Check: veil at 97 = 35 + floor(45*2/45) = 37, cleared instantly. Timer 97-50 = 47. Paused 97-200 = 103; active = 210-103 = 107.

### T13 "That was fine" teaches a rule (Standard)

```json
{"trace":"T13-that-was-fine","ticks":{"from":0,"until":300},"ignore":["RequestJudgment"],"prelude":{"preset":"Standard"},"steps":[
{"t":100,"ev":{"WindowChange":{"windowKey":"w:yt-lecture","siteKey":"s:youtube"}},"fx":[]},
{"t":103.5,"ev":{"Judgment":{"observedAt":100,"windowKey":"w:yt-lecture","contentKey":"c:l1","label":"off_task","strong":true}},"repeat":{"every":14,"until":187.5},"fx":[]},
{"t":125,"ev":"Tick","fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":30,"seconds":30}},{"OffTopicTimer":{"seconds":25,"running":true,"visible":true}}]},
{"t":175,"ev":"Tick","fx":[{"Beacon":{"state":"interrupted"}},{"Veil":{"from":30,"to":60,"seconds":30}},{"Interrupt":{"kind":"card","severity":1,"block":1,"windowKey":"w:yt-lecture"}}]},
{"t":180,"ev":{"UserAction":{"action":"that_was_fine"}},"fx":[{"Withdraw":{"what":"card"}},{"Beacon":{"state":"resting"}},{"Veil":{"from":35,"to":0,"seconds":5}},{"OffTopicTimer":{"seconds":80,"running":false,"visible":false}},{"LearnRule":{"scope":"project","kind":"allow","keyType":"window","key":"w:yt-lecture"}}]},
{"t":200,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[]},
{"t":260,"ev":{"WindowChange":{"windowKey":"w:yt-lecture","siteKey":"s:youtube"}},"fx":[]},
{"t":300,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":300,"offTopicSeconds":0,"unsureSeconds":0,"drifts":0,"interrupts":1,"refusals":0}}]}
]}
```
Check: the 187.5 judgment (STRONG) arrives after the rule exists and is ignored. At 260 the session rule makes the lecture ON with no judgment. The forgiven block is not counted; the interrupt that happened is.

### T14 Sensitive window: never judged, block frozen and resumed

```json
{"trace":"T14-sensitive","ticks":{"from":0,"until":150},"ignore":[],"steps":[
{"t":0,"ev":{"SessionStart":{"preset":"Standard"}},"fx":[{"Beacon":{"state":"resting"}},{"Clock":{"seconds":0,"running":true}}]},
{"t":0,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[{"RequestJudgment":{"id":1,"reason":"window_change","urgency":"now","windowKey":"w:editor"}}]},
{"t":3.5,"ev":{"Judgment":{"requestId":1,"observedAt":0,"windowKey":"w:editor","contentKey":"c:e1","label":"on_task"}},"fx":[]},
{"t":12,"ev":"Tick","fx":[{"RequestJudgment":{"id":2,"reason":"cadence","urgency":"normal","windowKey":"w:editor"}}]},
{"t":15.5,"ev":{"Judgment":{"requestId":2,"observedAt":12,"windowKey":"w:editor","contentKey":"c:e1","label":"on_task","source":"unchanged"}},"fx":[]},
{"t":20,"ev":{"SensitiveEntered":{}},"fx":[{"Beacon":{"state":"paused","reason":"sensitive"}}]},
{"t":50,"ev":{"SensitiveLeft":{}},"fx":[{"Beacon":{"state":"resting"}}]},
{"t":50,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[]},
{"t":60,"ev":{"WindowChange":{"windowKey":"w:yt"}},"fx":[{"RequestJudgment":{"id":3,"reason":"window_change","urgency":"now","windowKey":"w:yt"}}]},
{"t":63.5,"ev":{"Judgment":{"requestId":3,"observedAt":60,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"fx":[]},
{"t":68,"ev":"Tick","fx":[{"RequestJudgment":{"id":4,"reason":"cadence","urgency":"high","windowKey":"w:yt"}}]},
{"t":71.5,"ev":{"Judgment":{"requestId":4,"observedAt":68,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"fx":[]},
{"t":85,"ev":"Tick","fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":30,"seconds":30}},{"OffTopicTimer":{"seconds":25,"running":true,"visible":true}}]},
{"t":76,"ev":"Tick","fx":[{"RequestJudgment":{"id":5,"reason":"cadence","urgency":"high","windowKey":"w:yt"}}]},
{"t":90,"ev":{"SensitiveEntered":{}},"fx":[{"Beacon":{"state":"paused","reason":"sensitive"}},{"Veil":{"from":5,"to":0,"seconds":5}},{"OffTopicTimer":{"seconds":30,"running":false,"visible":false}}]},
{"t":91.5,"ev":{"Judgment":{"requestId":5,"observedAt":76,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"fx":[]},
{"t":120,"ev":{"SensitiveLeft":{}},"fx":[{"Beacon":{"state":"resting"}}]},
{"t":120,"ev":{"WindowChange":{"windowKey":"w:yt"}},"fx":[{"RequestJudgment":{"id":6,"reason":"window_change","urgency":"now","windowKey":"w:yt"}}]},
{"t":123.5,"ev":{"Judgment":{"requestId":6,"observedAt":120,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":30,"seconds":30}},{"OffTopicTimer":{"seconds":33.5,"running":true,"visible":true}}]},
{"t":128,"ev":"Tick","fx":[{"RequestJudgment":{"id":7,"reason":"cadence","urgency":"high","windowKey":"w:yt"}}]},
{"t":150,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Veil":{"from":26,"to":0,"seconds":5}},{"OffTopicTimer":{"seconds":60,"running":false,"visible":false}},{"Summary":{"activeSeconds":150,"offTopicSeconds":60,"unsureSeconds":0,"drifts":1,"interrupts":0,"refusals":0}}]}
]}
```
Check: the cadence check due at 33.5 is cancelled by the hold (no request at 34 or at 50); the editor is a cache hit at 50 → next check 140, superseded at 60. 63.5+10 → tick 74; 77.5+10 → tick 88. Sensitive at 90 freezes the block at 30 (veil at 90 = floor(30*5/30) = 5); the in-flight answer at 91.5 is discarded. Resume at 120 (120-90 = 30 ≤ 120): timer 30 + 3.5 = 33.5. Veil at 150 = floor(30*26.5/30) = 26; timer 30 + 30 = 60. Clock never stops (sensitive is a quiet hold).

### T15 Re-drift within 2 minutes resumes the timer (Standard)

```json
{"trace":"T15-redrift-resume","ticks":{"from":0,"until":240},"ignore":["RequestJudgment"],"prelude":{"preset":"Standard"},"steps":[
{"t":100,"ev":{"WindowChange":{"windowKey":"w:reddit"}},"fx":[]},
{"t":103.5,"ev":{"Judgment":{"observedAt":100,"windowKey":"w:reddit","contentKey":"c:r1","label":"off_task","strong":true}},"repeat":{"every":14,"until":145.5},"fx":[]},
{"t":125,"ev":"Tick","fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":30,"seconds":30}},{"OffTopicTimer":{"seconds":25,"running":true,"visible":true}}]},
{"t":150,"ev":{"WindowChange":{"windowKey":"w:editor"}},"fx":[{"Veil":{"from":25,"to":25,"seconds":0}},{"OffTopicTimer":{"seconds":50,"running":false,"visible":true}}]},
{"t":165,"ev":"Tick","fx":[{"Beacon":{"state":"recovering"}},{"Veil":{"from":25,"to":0,"seconds":5}},{"OffTopicTimer":{"seconds":50,"running":false,"visible":false}}]},
{"t":170,"ev":"Tick","fx":[{"Beacon":{"state":"resting"}}]},
{"t":200,"ev":{"WindowChange":{"windowKey":"w:reddit"}},"fx":[]},
{"t":203.5,"ev":{"Judgment":{"observedAt":200,"windowKey":"w:reddit","contentKey":"c:r2","label":"off_task","strong":true}},"fx":[{"Beacon":{"state":"drifting"}},{"Veil":{"from":0,"to":30,"seconds":30}},{"OffTopicTimer":{"seconds":53.5,"running":true,"visible":true}}]},
{"t":217.5,"ev":{"Judgment":{"observedAt":214,"windowKey":"w:reddit","contentKey":"c:r3","label":"off_task","strong":true}},"fx":[]},
{"t":225,"ev":"Tick","fx":[{"Beacon":{"state":"interrupted"}},{"Veil":{"from":21,"to":60,"seconds":39}},{"Interrupt":{"kind":"card","severity":1,"block":1,"windowKey":"w:reddit"}}]},
{"t":240,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Veil":{"from":36,"to":0,"seconds":5}},{"OffTopicTimer":{"seconds":90,"running":false,"visible":false}},{"Summary":{"activeSeconds":240,"offTopicSeconds":90,"unsureSeconds":0,"drifts":1,"interrupts":1,"refusals":0}}]}
]}
```
Check: return at 150 with timer 50; veil at 150 = floor(30*25/30) = 25. Re-drift observed at 200: 200-150 = 50 ≤ 120 → block 1 resumes at 50 and is past grace at once. The pair is different content (r2, r3) 14 s apart (≥ 10). Timer 75 at 50 + 25 → t = 225; veil at 225 = floor(30*21.5/30) = 21. At 240: 21 + floor(39*15/39) = 36; timer 50 + 40 = 90. A fresh block would have nudged at 275.

### T16 Shadow mode never nudges (Standard)

```json
{"trace":"T16-shadow","ticks":{"from":0,"until":180},"ignore":["RequestJudgment"],"prelude":{"preset":"Standard","shadow":true},"steps":[
{"t":100,"ev":{"WindowChange":{"windowKey":"w:yt"}},"fx":[]},
{"t":103.5,"ev":{"Judgment":{"observedAt":100,"windowKey":"w:yt","contentKey":"c:yt1","label":"off_task","strong":true}},"repeat":{"every":14,"until":173.5},"fx":[]},
{"t":175,"ev":"Tick","fx":[{"ShadowMark":{"block":1,"kind":"card","windowKey":"w:yt"}}]},
{"t":180,"ev":{"SessionEnd":{"reason":"user"}},"fx":[{"Beacon":{"state":"off"}},{"Summary":{"activeSeconds":180,"offTopicSeconds":80,"unsureSeconds":0,"drifts":1,"interrupts":0,"refusals":0}}]}
]}
```
Check: the state machine runs as in T10 (Drifting at 125, confirmed at 175), but the ring stays at resting, there is no veil or timer, and the would-be card becomes a `ShadowMark` for the review queue.

### 9.2 Coverage

| Requirement | Traces |
|---|---|
| Backoff, cache, request IDs | T01, T07, T14 |
| Grace, drain, timer, return 15 s, recovery 5 s | T02, T03, T04, T15 |
| Confirm via same-content time separation | T03, T04, T05, T10 |
| Confirm via different content | T15 |
| Rate cap defers an interrupt | T03 |
| Gate, BringBack, re-entry prompt | T04 |
| NEUTRAL never interrupts; weak off is NEUTRAL | T06, T07 |
| Refusal flag overrides label | T07 |
| Holds: idle, meeting, break, snooze, panic, sensitive | T08, T09, T10, T11, T12, T14 |
| Timed clock, extend, wrap-up, timer end | T09 |
| Forgiveness and rule learning | T13 |
| Shadow mode | T16 |

Not yet covered, to add with the first implementation: `PowerChange`, `Sleep`/`Wake`, `ignore_window`, `mark_relevant`, `dismiss`, a gate repeat in Strict (where the 3-minute repeat meets the rate cap at the third interrupt), `ruleLabel = off_task`, out-of-order and stale judgments, and property tests (PLAN 9.3): no `Interrupt` without a STRONG latest evidence, never two `Interrupt` within 600 s more than twice, veil never above cap, every hold clears veil and timer.


## Addendum (2026-10-01): never-judged windows

`WindowChangeInput.ruleLabel` may be `unsure`. The brain treats it as NEUTRAL evidence with source rule and issues no `RequestJudgment` for that window (same as an on_task rule for requests). It never advances past Drifting. Used for the default never-judged list (personal messaging, music, blank pages). The golden traces do not use it; `ReadingTests.NeverJudgedTests` covers it end to end.


## Addendum (2026-10-15): choosing a smaller task within a session

`TaskChanged{}` is an explicit evidence boundary when the user accepts an on-device next action. It is processed before time-driven confirmation at that event's timestamp. Close/count the previous evidence block, withdraw any old interrupt/re-entry, and reset focus to OnTask. Clear the window, cached on/refused judgments, session-only rules, last evidence/return target, streaks, in-flight request and next-check deadline. Reject subsequent callbacks with a request ID below the next request ID at this boundary. The controller cancels its old asynchronous jobs and follows with a fresh WindowChange for the current window.

Preserve the session clock, start/duration, holds, accumulated statistics, interruption rate-cap history, project rules and user settings. Timed end is still evaluated after the event. No nudge for the new goal may rely on the previous task's evidence. Goal text stays in the UI/judge layer; the pure brain receives no screen or task prose.

### T17 Task change invalidates cached evidence without restarting time

```json
{"trace":"T17-task-change","ignore":["Beacon","Veil","OffTopicTimer","Clock","Withdraw","ReentryPrompt","WrapUp","AskResume","ShadowMark","LearnRule","BringBack","Cue"],"steps":[{"t":0,"ev":{"SessionStart":{"mode":"Open","preset":"Standard"}},"fx":[]},{"t":0,"ev":{"WindowChange":{"windowKey":"w:work"}},"fx":[{"RequestJudgment":{"id":1,"reason":"window_change","urgency":"now","windowKey":"w:work","allowVision":true}}]},{"t":1,"ev":{"Judgment":{"requestId":1,"observedAt":0,"windowKey":"w:work","contentKey":"c:work","label":"on_task"}},"fx":[]},{"t":2,"ev":{"TaskChanged":{}},"fx":[]},{"t":2,"ev":{"WindowChange":{"windowKey":"w:work"}},"fx":[{"RequestJudgment":{"id":2,"reason":"window_change","urgency":"now","windowKey":"w:work","allowVision":true}}]},{"t":3,"ev":{"Judgment":{"requestId":1,"observedAt":2,"windowKey":"w:work","contentKey":"c:old","label":"off_task","strong":true}},"fx":[]},{"t":4,"ev":{"Judgment":{"requestId":2,"observedAt":2,"windowKey":"w:work","contentKey":"c:new","label":"on_task"}},"fx":[]},{"t":6,"ev":{"SessionEnd":{}},"fx":[{"Summary":{"activeSeconds":6,"offTopicSeconds":0,"unsureSeconds":0,"drifts":0,"interrupts":0,"refusals":0}}]}]}
```
