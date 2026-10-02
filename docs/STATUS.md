# Status for the owner (written 2026-10-02, while you were away)

Everything here is on this Mac only. Nothing was pushed or published. Windows code cannot be run here, so nothing about Windows is verified.

## Fixed since you last used it
- **Hover crash on the notch/pill.** Reproduced with synthetic pointer moves, fixed (the SwiftUI view is no longer the window's content view). `tools/check_notch_hover.sh` re-runs the check.
- **Monitor unplug crash.** The panel now re-places itself on display changes (`didChangeScreenParameters`) and hides when no screen exists. Not verified against a real unplug.
- **Permissions kept getting lost.** Each rebuild changed the app's signature, so macOS dropped Accessibility and Screen Recording. The bundle is now signed with a stable requirement. You must remove and re-add Focus once in Privacy & Security (Accessibility, and Screen Recording if you use screen reading).
- Permission card on Today appears between sessions and disappears once allowed; the system dialog is raised once per launch.
- Window titles now also work with Screen Recording alone.

## Added
- **Screen reading** (opt-in): picture of the front window on Today, words read by Apple Vision (fast level) and added to the judge's window text. Memory only; skips private and never-judged windows; drops text that looks like a login or payment screen. Unverified on a real display (needs your Screen Recording grant).
- **Try it** (Settings): a 5-second countdown, then shows what Focus can see in the window you switched to. Use this to check sensing.
- **System signals**: idle (4 min), sleep or screen lock, Low Power Mode or heat, and calls (camera on, or microphone with a conferencing app in front) pause or slow the brain as the spec says.
- **First run**: one-screen intro (skipped if you already have sessions); one-time "too quiet, about right, too loud" after the first session that actually nudged.
- **Level 0 start**: the start sheet opens on your last project with its next step. Global shortcut Control-Option-F (start, or pause/resume). Session menu and View shortcuts (Command-1 to 6).
- **Nudges reach you in the background**: they show in the notch/pill even if you hid it; the strict pause screen brings the window forward; "Back to task" activates the app you were last on task in.
- Prompt-injection guard (see `docs/T7-injection.md`) with its limits.

## Decisions I made without asking (change any of them)
- OCR level `.fast` (accurate stalled about 66 s on first use).
- Idle threshold 240 s; call needs two polls in a row (about 10 s).
- Microphone alone is not a call (something holds it open all day on this Mac).
- Global shortcut is Control-Option-F.
- Screen reading is off until you switch it on; the picture refreshes every 3 s, words every 8 s.

## Still unverified or not built
- Real unplug of a monitor; global shortcut key delivery (registration returned success, a synthetic key press did not trigger it); Screen Recording capture; Accessibility title reading (this shell is not trusted, so I could not run it).
- Accuracy numbers are from synthetic scenarios (`docs/S1-accuracy.md`); fresh-set strict precision 71%, recall 40% on clear distractions. Real windows are untested.
- Privacy tests T1 to T4 (sandbox) not done, so the "cannot reach the network" claim stays banned.
- Windows: nothing runnable here.
- Still yours to decide: product name, audience, pricing, open-sourcing, minimum OS, Mac distribution, languages.
