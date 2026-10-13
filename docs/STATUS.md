# Status for the owner (written 2026-10-02, while you were away)

Everything here is on this Mac only. Nothing was pushed or published. Windows code cannot be run here, so nothing about Windows is verified.

## Fixed since you last used it
- **Hover crash on the notch/pill.** Reproduced with synthetic pointer moves, fixed (the SwiftUI view is no longer the window's content view). Also fixed: hover never opened the panel while Focus was in the background and flickered when it did (SwiftUI hover reported "left" a few milliseconds after "entered"); an AppKit tracking area now owns hover. `tools/check_notch_hover.sh` moves the real pointer onto the panel and checks it survives and grows from 32 to 120 points (measured). The pill now sits under the menu bar on screens without a notch.
- **Monitor unplug crash.** The panel now re-places itself on display changes (`didChangeScreenParameters`) and hides when no screen exists. Not verified against a real unplug.
- **Permissions kept getting lost.** Each rebuild changed the app's signature, so macOS dropped Accessibility and Screen Recording. The bundle is now signed with a stable requirement. You must remove and re-add Focus once in Privacy & Security (Accessibility, and Screen Recording if you use screen reading).
- Permission card on Today appears between sessions and disappears once allowed; the system dialog is raised once per launch.
- Window titles now also work with Screen Recording alone.

## Added
- **Screen reading** (opt-in): picture of the front window on Today, words read by Apple Vision (fast level) and added to the judge's window text. Memory only; skips private and never-judged windows; drops text that looks like a login or payment screen. Unverified on a real display (needs your Screen Recording grant).
- **Try it** (Settings): a 5-second countdown, then shows what Focus can see in the window you switched to. Use this to check sensing.
- **System signals**: idle (4 min), sleep or screen lock, Low Power Mode or heat, and calls (camera on, or microphone with a conferencing app in front) pause or slow the brain as the spec says.
- **First run**: one-screen intro (skipped if you already have sessions); one-time "too quiet, about right, too loud" after the first session that actually nudged.
- **Typed duration**: "calc homework 50" starts a 50-minute timed session.
- **Level 0 start**: the start sheet opens on your last project with its next step. Global shortcut Control-Option-F (start, or pause/resume). Session menu and View shortcuts (Command-1 to 6).
- **Nudges reach you in the background**: they show in the notch/pill even if you hid it; the strict pause screen brings the window forward; "Back to task" activates the app you were last on task in.
- Prompt-injection guard (see `docs/T7-injection.md`) with its limits.

## Checked end to end with the real Apple model (scripted windows, fake clock; no real screen)
- Notes on the task, then a video site: the nudge card came 55 s after the switch (Standard preset). Opt-in test: `FOCUS_E2E=1 swift test --filter RealModelE2ETests`.
- Nine minutes of on-task developer windows (editor, terminal, Stack Overflow, pull request, Slack, Postman): 0 nudges. But the model said "Not sure" for most of them (only the pull request page read as "On task"), so the reading card will often say "Not sure" during real work. That is the conservative failure (nothing happens), not a false nudge; it is also why the headline recall is low. Sample of one task, not a measurement. Adding a project description that named all of those windows barely changed it (one more window read as on task), so do not promise users that describing a project fixes "Not sure".

## Matching-words rule (new, my decision, Settings switch "Count matching words as on task")
The model said "Not sure" for most real work windows, so a window whose title, page path or file path shares a distinctive word with the task or project description now counts as on task without asking the model (never on feeds, video or news sites; project allow/never rules and the never-judged list still win). On all three scenario sets it settles 33 of 62 on-task moments and waves through 2 of 45 off-task moments (both gray) and 0 of 40 unsure ones. It can only make Focus quieter, so it costs recall (a distraction sharing a word goes unnoticed), never a false nudge. These sets were also used to design it, so the numbers are a cost estimate, not held-out accuracy. It saves model calls too. With the real model, the developer-window sequence went from 1 of 9 reads "On task" to 7 of 9, and a video-site distraction still nudged at the expected time.

**Update:** the rule now also counts the app's name when the task names it ("notes in TextEdit"), except for browsers. Found by driving the real app: a README in TextEdit under that task read "Not sure". Cost on the scenario sets: off-task waved through 3 of 45 (was 2): two Figma/Android Studio gray cases where the task names the app but the window is another project. Still only quieter, never louder.

## Two displays and the notch (owner asked 2026-10-02; verified on this Mac: external LF24T35 as primary, notched built-in on its right)
- **Cause found:** the pill followed `NSScreen.main`, which follows the key window. With the external monitor as main, the ring sat under the external menu bar instead of in the notch, and would jump between displays as focus moved.
- **Now:** the resting ring stays on a home screen: the notched built-in if there is one, else the primary screen. Measured: panel centred on the hardware notch, flush with the top (32 pt tall at rest, 120 on hover). A nudge also shows a pill on the screen the pointer is on, if that is a different screen (measured on the external: a second panel appeared at nudge time). The pointer is read when the nudge appears, not followed afterwards.
- The Strict pause screen moves the Focus window to the pointer's screen before coming forward (measured: window moved from the external to the built-in).
- Each panel has its own hover state; 120 pointer moves across both displays and the notch did not crash the app. Real unplug of a display is still untested; the code drops panels for screens that no longer exist.
- Also fixed on the way: "Start a session" in the menu bar menu (it only had Open Focus), the popover now closes after a click, project name clipped, chips vs typed length, paused footer, "1 minutes".
- Tooling note: the computer-use click lands about 98 px too high on this two-display setup (external is 1080 high, built-in 982); mouse moves are exact. Escape sent by that tool does not reach the app; Command-period does.

## Why clear distractions said "Not sure" (owner report 2026-10-02) and what changed
- **Cause (measured with the real model):** the first judge flagged the distraction correctly, but the second judge wrote a correct reason ("unrelated to the lab report") and then picked the category "supporting" for nearly every window, and the two-judge rule treated that as a veto. On 82 scenarios that reach the model in the app, recall on clear distractions was 47% (17 of 36).
- **Now:** (1) the second opinion is a plain question, "does this serve the task / unrelated / can't tell" (`core/prompts/instructions_v3.txt`); (2) the first judge must report confidence 95 or more before a window can count as off task (every off-task call that was really on-task work had 90 or less; the model says 95 when it is sure); (3) general-purpose apps (Finder, Terminal, Mail, Calendar, System Settings, Activity Monitor) are neutral, not judged, unless a project rule or the task names the app.
- **Result on a fresh set written before the change (39 scenarios, one run):** 11 of 15 off-task windows flagged, the other 4 stay "Not sure"; 0 of 12 on-task and 0 of 12 neutral windows flagged. On the older (spent) sets the same rule gave 88% recall with 0 on-task false flags, plus about 12 gray neutral windows (feeds, lofi video, LinkedIn) flagged, which are the cost. Small samples, one labeler; the thresholds were chosen on the older sets. Nudges still need sustained agreement in the brain, so one flagged window does nothing by itself.
- **New switch (Settings): "Judge with the on-device model"**, on by default. Off means rules and matching words only, everything else "not judged".
- **Wrong picture on Today:** the capture used the front app's biggest window, so a browser with several windows was read through another window (the words were from a different page). It now takes the topmost window of the app. Needs your Screen Recording grant to try for real.
- Tools: `FOCUS_PROBE=1 swift test --filter JudgeProbeTests` prints what each judge says about realistic windows; `FOCUS_LAB=1` compares second judges; `FOCUS_LAB_FINAL=scenarios_fresh2 swift test --filter JudgeLabTests/testShippedPipeline` runs the shipped pipeline on a set. `eval/scenarios_fresh2/` is the new set (spent after this run).
- The Python eval harness still describes the old relation judge (docs/S1-accuracy.md numbers are for it).

## Notch animation (owner report 2026-10-02)
The window used to snap to its new size while the SwiftUI shape animated inside it. Now the window keeps one size (the biggest mode) and only the black shape animates, with a spring; the ring and time stay put; the body fades in and out; hover opens after 0.16 s so passing the pointer by does not pop it open, and closes after 0.1 s. Frames captured while hovering showed the fade; the shape growth itself could not be seen against this Mac's black wallpaper.

## Nudge wording and quiet rewards (owner asked 2026-10-13: "nudge features and reward systems that keep you on track")
- **Nudges:** three tones (Neutral, Coach, Direct) of curated lines, never model-written, none naming the window. After a detour of 8 minutes or more the card, the notch and the Strict pause screen lead with "Take a 5 minute break" and keep "Back to task" one click away. Optional soft system tone (Tink), off by default, never in practice mode.
- **Rewards, all from saved seconds (no text):** a daily goal (default 90 min), focus days (20 min on task) with up to 2 rest days a week so a missed day never breaks a streak, longest stretch without a slip, and time to get back on task after a flagged drift. A closed ring with a tick plus a short line ("Back in 40 s", "Daily goal reached", "Longest stretch yet") shows for 8 s while working; one line ends each session. Insights has a "Getting back on track" panel. Settings: "Progress" group (switch, goal) and tone/sound under Nudges.
- **Held to PRODUCT.md principle 6:** no points, levels or badges, nothing taken away, no "streak at risk" copy, a rough session gets kindness not a score. Practice sessions are excluded from stretches and returns (their beacon never leaves "resting").
- **Verified:** 176 tests pass (6 opt-in real-model tests skipped), including controller tests driving a drift and return through the real controller. Rendered with `focus-snapshot` (seeded store) and the demo app's self-render: Today progress panel, Insights panel, Settings, notch nudge. Found and fixed by rendering: the goal read 0 between sessions (only computed at session start).
- **Not verified:** the in-session confirmation, the long-detour break card and the sound on a real display and real session (only logic tests and offscreen renders); the Rust brain is untouched, so the sound cue is the only brain-side behavior and it already existed. Windows: nothing.
- **Decisions I made:** 90 min default goal, 20 min focus day, 2 rest days a week, 8 minute detour threshold, 5 minute break offer, Tink as the tone, confirmations for 8 s. All are constants in `Rewards.swift` / `NudgeCopy.swift`.

## Decisions I made without asking (change any of them)
- OCR level `.fast` (accurate stalled about 66 s on first use).
- Idle threshold 240 s; call needs two polls in a row (about 10 s).
- Microphone alone is not a call (something holds it open all day on this Mac).
- Global shortcut is Control-Option-F.
- Screen reading is off until you switch it on; the picture refreshes every 3 s, words every 8 s.

## How I debugged
Early on I did not drive your screen (synthetic events sent to the process do nothing, and global ones could land on your windows). Computer control was later granted (then full control), so I drove a **demo copy** (`FOCUS_DEMO=1`, in-memory store, so your real data was never touched) with real accessibility clicks and typing: start sheet (typed "calc homework 50", started a timed session), Pause, End session, Projects (new project, typed description, "Ask Focus about a window"), and Settings "Try it" on your real instance (it correctly reported the front app only, because Accessibility is not granted for this build). Bugs found that way and fixed: project name clipped under its subtitle; Open/Timed chips disagreed with a typed length; the "Focus is watching" footer stayed while paused. The self-render (`FOCUS_SELFSHOT`) is still used for screenshots.

## Still unverified or not built
- Real unplug of a monitor; global shortcut key delivery (registration returned success, a synthetic key press did not trigger it); Screen Recording capture; Accessibility title reading (this shell is not trusted, so I could not run it).
- Accuracy numbers are from synthetic scenarios (`docs/S1-accuracy.md`); fresh-set strict precision 71%, recall 40% on clear distractions. Real windows are untested.
- Privacy tests T1 to T4 (sandbox) not done, so the "cannot reach the network" claim stays banned.
- Windows: nothing runnable here.
- Whether Chrome reports page addresses through Accessibility is unknown (Safari does). Without an address, titles still work, and the matching-words rule also skips pages whose title names a video or social site.
- Still yours to decide: product name, audience, pricing, open-sourcing, minimum OS, Mac distribution, languages.
