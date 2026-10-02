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

## Decisions I made without asking (change any of them)
- OCR level `.fast` (accurate stalled about 66 s on first use).
- Idle threshold 240 s; call needs two polls in a row (about 10 s).
- Microphone alone is not a call (something holds it open all day on this Mac).
- Global shortcut is Control-Option-F.
- Screen reading is off until you switch it on; the picture refreshes every 3 s, words every 8 s.

## How I debugged without driving your screen
You declined computer control, so I did not click or type in the app. Synthetic key and mouse events sent to the app's process did nothing, and I did not send global ones that could land on your other windows. Instead: the demo build renders its own windows to PNG (`FOCUS_SELFSHOT`), runs a few controller actions on a timer (`FOCUS_DEMO_ACTIONS=section:settings,start`), and the real pointer was moved onto the notch panel only for the hover check. Rendered and looked at: Today (idle, intro, in session, drifting), Settings, the start sheet, the notch at rest and open. Not exercised through real clicks or typing: the start sheet's text field and buttons, Review and Projects forms.

## Still unverified or not built
- Real unplug of a monitor; global shortcut key delivery (registration returned success, a synthetic key press did not trigger it); Screen Recording capture; Accessibility title reading (this shell is not trusted, so I could not run it).
- Accuracy numbers are from synthetic scenarios (`docs/S1-accuracy.md`); fresh-set strict precision 71%, recall 40% on clear distractions. Real windows are untested.
- Privacy tests T1 to T4 (sandbox) not done, so the "cannot reach the network" claim stays banned.
- Windows: nothing runnable here.
- Whether Chrome reports page addresses through Accessibility is unknown (Safari does). Without an address, titles still work, and the matching-words rule also skips pages whose title names a video or social site.
- Still yours to decide: product name, audience, pricing, open-sourcing, minimum OS, Mac distribution, languages.
