# Real-use core-loop test

Step 0 · 2026-10-15 · **23 minutes plus permission setup** · awaiting Aarav's results.

Automated tests and demo renders do not prove real sensing or model accuracy. Run this yourself; paste back the result lines, not screenshots, OCR or the store. Step 1 waits until failures are reviewed and fixed, false nudges first.

## Prepare

1. Quit other Focus copies yourself. Close personal windows and notifications. Use only these fabricated pages and an empty Music library; no real conversations, documents or credentials.
2. Launch the built bundle from the repo:

   ```sh
   cd ~/focus-app
   open -n --env FOCUS_TEST_STORE="$TMPDIR/focus-test" mac/.build/Focus.app
   ```

   Do not set `FOCUS_DEMO=1`: it bypasses real sensing. Test history is `$TMPDIR/focus-test/store.json`; test preferences use `focus-app.test.focus-test`. Reusing that folder reuses its test settings. Normal Focus history/settings are separate.
3. Grant **Accessibility** and **Screen Recording** to this bundle in System Settings > Privacy & Security. Relaunch if requested. If an old grant appears enabled but fails after rebuilding, remove and re-add this bundle yourself. I cannot grant permissions.
4. Set **Standard / Often / Proactive**. For repeatable timing, turn **Ease in, then push harder when behind** off. Turn **If you stay away after a warning** off to isolate the core loop from full-screen enforcement. Keep the notch and reminder banner on; early **Heads-up before a warning**, sound, speech, scheduled prompts, **Hold to go back to your task** and the iPhone link off. These are test settings, not changed product defaults.
5. In **What Focus reads**, keep the model and never-judged list on; turn screen reading on. Turn **Count matching words as on task** off so the work page reaches the model. Use no project allow/never/folder rules. If Today reports an unavailable model, missing permission or only app names, report **BLOCKED**, not PASS. Do not download a model just for this test without discussing it.
6. Open the offline fixtures in separate tabs of one normal Safari window:

   ```sh
   open -a Safari docs/real-use-fixtures/work.html
   open -a Safari docs/real-use-fixtures/drift.html
   open -a Safari docs/real-use-fixtures/login.html
   ```

   The feed is static fabricated entertainment, with no playable video, scripts, external assets or network requests. This tests real browser-window sensing on synthetic content; a live website remains a separate check. Keep the text readable. Record Low Power Mode if enabled.
7. Start an **Open** session: **Calc homework: integration by parts**. Keep that task unchanged if the coach offers a rewrite. In Projects, set context: **Practice integration by parts. Calculus lessons, worked integral examples and my written solutions count.** Return to `work.html`.

Setup: PASS / FAIL / BLOCKED ___; build ___; macOS ___; browser ___; Accessibility ___; Screen Recording ___; model ready ___; power mode ___; setting differences ___

## Observe without changing what is being tested

Today already shows the session state, current verdict, reason, reading age, **All readings**, preview and **Words Focus read** disclosure. Select **Back to now** if you pinned an old reading. Keep Safari frontmost during each block; briefly inspect Today between blocks, then switch back. Focus does not sense its own front window, so waiting in Today can make the reading age grow. Use a watch or phone clock, without the companion app.

With Standard + Often, fake-clock tests warn about **45 seconds** after sustained drift (Normal: 75 seconds). Real model/OCR latency can delay it: allow up to **3 minutes**. One off-topic verdict alone is insufficient. `Not sure` must not confirm a nudge; on the clearly unrelated feed, persistent uncertainty is a detection miss, not a successful drift test. Pictures refresh nominally every 3 seconds, OCR every 8 seconds; power constraints slow capture.

## Run

| Time | What you do | Expected in Today | Expected at the notch |
|---|---|---|---|
| **0–4 min: work** | Read `work.html`; solve the last exercise on synthetic scratch paper. Scroll occasionally to avoid the four-minute idle threshold. | Correct Safari tab, calculus preview/OCR, model-derived `On task` or conservative `Not sure`, task-related reason. **No nudge.** `Words matched` or `Your rule decided` means this did not test the model: recheck setup. | Normal task/time presence; no return button. |
| **4–7 min: drift** | Switch to `drift.html`, read/scroll, note first off-topic verdict and first confirmed nudge. Do not add rules. | Correct entertainment tab; sustained model `Off topic` should produce Drifting, then a warning. No shield, hidden app or closed tab with escalation off. A card can expire after about 12 seconds. | Expands for a calm task-focused nudge with **Back to task**. It never names the feed. A reminder banner may appear too. |
| **7–10 min: recover** | Press **Back to task** in the notch/banner/menu bar. If tab return fails, manually select `work.html` and report that separately. | Work becomes `On task`; about **15 seconds of continuous on-task evidence** precedes recovery, then gray clears over about **5 seconds**. Time from the first fresh on-task verdict, not the click. `Not sure` is not proof of recovery. | Nudge closes and normal task/ring returns; no later escalating reminder. |
| **10–12 min: never judged** | Bring **Music** forward on an empty library. No real Messages or playback. | `Not sure` / `Not judged`, title `Not read`, never-judged reason; preview/OCR absent. No new off-topic warning. Neutral evidence can have an unsure/drifting ring without confirmation. | No fresh nudge; task/time and neutral state may remain. |
| **12–14 min: reset** | Return to `work.html` until a current on-task verdict settles the ring. | Correct work preview/OCR returns; no lingering warning. | Normal task presence. |
| **14–16 min: login** | Open `login.html` in the same normal window. Enter nothing. | OCR sees fabricated Password/Passcode/Verification code labels, then drops picture/words and shows **This looks private. Not read or shown.** No new nudge. Initial pixels can precede OCR; report a hold taking over 15 seconds on an unconstrained Mac. | No new nudge, login wording or stale warning. |
| **16–18 min: reset** | Return to `work.html` and wait for a fresh on-task verdict. | Work preview/OCR returns; no leftover privacy hold. | Normal task presence. |
| **18–20 min: lock** | Note elapsed/off-topic time. Press **Control-Command-Q**, stay locked about **90 seconds**, then unlock yourself with the work tab frontmost. | Sleep hold excludes the locked interval from active/off-topic time. A lock under five minutes resumes silently; longer absences should ask. No burst of overdue warnings. This checks behavior, not whether pixels were acquired in the background. | No new nudge due to lock; normal presence resumes after unlock. |
| **20–23 min: finish** | Work two more minutes, end through the app/menu bar, inspect History. | Plausible active time, counts and timeline; locked time excluded. Preview/OCR clears on ending. History contains counts/durations, not screen text; task/context you typed remain local. | Session presence tucks away; no leftover nudge or gray overlay. |

Safari may request Automation permission for tab return. Grant it yourself only if you want to test that action. Denial or a failed switch does not prevent manual recovery: report tab return and brain recovery separately.

**Login limit:** the OCR filter drops pixels/words but is not the brain's private-window hold. Title-only judgment may still occur; report any warning as a failure. One synthetic page does not prove all login pages are protected.

## Fill in one line per check

1. Work: PASS / FAIL ___; first model verdict after ___ s; verdict ___; reason fits ___; correct picture ___; OCR present ___; nudges ___
2. Drift: PASS / FAIL ___; first off-topic ___ s; drifting ___ s; nudge ___ s / none; notch expanded ___; wrong/stale picture ___; unexpected shield/hide/close ___
3. Recovery: PASS / FAIL ___; tab return PASS / FAIL / denied ___; first on-task after ___ s; normal ring after ___ s; gray cleared after ___ s; later unwanted nudge ___
4. Music: PASS / FAIL ___; Not judged ___; preview/OCR absent ___; new warning ___
5. Work reset: PASS / FAIL ___; on-task verdict ___; old warning cleared ___
6. Login: PASS / FAIL ___; privacy hold after ___ s; preview/OCR cleared ___; title-only verdict if any ___; new warning ___
7. Pre-lock reset: PASS / FAIL ___; fresh work preview/OCR ___; on-task verdict ___
8. Lock: PASS / FAIL ___; actual locked ___ s; elapsed before ___ / after ___; extra off-topic time ___; unexpected prompt/warning ___
9. Finish: PASS / FAIL ___; saved active time ___; drifts ___; nudges ___; preview/OCR cleared ___; leftover overlay/notch ___

If no nudge by three minutes, distinguish persistent `Not sure`, model failure, stale readings, and sustained `Off topic` without confirmation. Do not lower thresholds or add a deny rule to make it pass. Pause/end if anything feels wrong.

Paste **Setup plus these nine lines**, with only synthetic reasons and approximate timings. Keep the store local. This is a smoke test, not a precision/recall estimate. Fix order: privacy/false nudges → wrong-window/stale sensing → missed confirmation → recovery/tab return → visual/motion issues.

After baseline review, optionally repeat the drift/recovery block with matching words and escalation **on**, using the same fixtures, to check shipped behavior separately. Return at the first nudge. This extra run is outside the 23 minutes; Strict tab closing is out of scope.

## Implementation references

- `FocusUI/Views/TodayLive.swift` and `ReadingViews.swift`: existing memory-only diagnostics and privacy messages.
- `FocusUI/Storage/Preferences.swift`: actual Standard/Often/Proactive defaults and check scales.
- `FocusUI/SessionController.swift`: rule/model paths, private-word handling and recovery surfaces.
- `FocusSense/SystemWatcher.swift`: lock signals and four-minute idle threshold.
- `docs/BRAIN-SPEC.md` §§3.3, 4.3–4.4, 6.1: holds, sustained evidence, 15-second return and 5-second recovery. Code/Status include later changes to the plan's original timing.

Step 0 adds no debug panel, stored debug text, runtime default changes or brain changes. HTML fixtures are Safari test input, not app web views.
