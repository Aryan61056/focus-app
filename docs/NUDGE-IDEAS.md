# Ways to get you back on track (2026-10-16)

Owner ask: "find more better ways to nudge", get Back to task to the correct area, and more ideas like removing the color from the screen.
All of it stays inside the rules in CLAUDE.md: on-device, nothing pushed names the distraction, a false nudge costs more than a miss, and every new cue is a switch the user can turn off.

## What already existed
Heads-up banner, reminder banner, notch card, menu bar tint, Dock bounce, trackpad taps, voice, the gray screen, check-in, pause screen, hiding the app, switching or closing the tab, the cover when the same site opens again, scheduled check-ins and breaks. See `Cues.swift`, `Escalation.swift`.

## Built in this pass
| Idea | What it does | Switch |
|---|---|---|
| **Back to task goes to the place** | Remembers the few windows, tabs and documents you worked in (names only, memory only, dropped with the session) and how long you stayed in each. Goes to the one you settled in (45 s or more), else the one you spent the most time in, so a glance at a reference never becomes "the task". Raises the exact window (Accessibility: same file, then same title), or the exact tab in any browser (AppleScript: by address, then by title), even when you have already left for another app. If it cannot find the place it tries the next, and says it only reached the app. | Settings > Switch back to your tab (tabs only) |
| **Pick from the menu** | The menu bar shows where Back to task lands (icon and short name) and up to two other places to go instead. Tooltips and VoiceOver say the same on the banner, cards, notch and pause screen. | none |
| **Landing ring** | A soft ring on the window that came forward, for about a second and a half. Fainter when only the app came forward. A reward, not a nudge; no motion with Reduce Motion. | Settings > Ring the window you land in (on) |
| **Close in the edges** | The edges of every display darken and close toward the middle as you stay away, the middle stays readable, it opens again when you return. Same ramp as the gray; works with it or alone. | Settings > Close in the edges (off) |

## Not built: ranked suggestions for you to pick from
1. **Quiet only the window you drifted into.** The gray or dim covers just that window's frame, so the task window beside it stays in full color and looks like the way back. Targeted instead of whole-screen. Needs a look on a real display: overlapping windows and moving windows decide whether it feels right.
2. **Pick up where you left off.** After Back to task, a short chip with the project's saved next step ("Next: finish paragraph 2"), for four seconds. Reuses what the user already wrote; no new data.
3. **Learn what works for you.** Time to return is already recorded per drift. Record which cue was showing, show the medians in Insights ("The gray brings you back about 40 s sooner than the banner"), and start with the cue that works for that person. Measure before it decides anything.
4. **Cursor halo.** A ring around the pointer that grows the longer you are away. Hard to ignore without covering anything. Costs a little CPU while away, so it needs a measurement against the 2 percent budget.
5. **Lower the sound.** System volume eases down while you are off task on a video or music site and comes back when you return. Strong for video rabbit holes. Risks: a call or headphones in use (the call detector would have to hold it), and a crash must never leave the volume low.
6. **Fog.** A progressive blur of the screen. Same private layer as the gray. Harsh, so it is your call.
7. **A macOS Focus mode at session start** (Do Not Disturb filter through Shortcuts). Removes the notifications that cause drifts. Needs the user to install a Shortcut.
8. **Drift reason after you return** (PLAN F2): one tap, "stuck, bored, tired, a notification". "Stuck" opens the next-step helper that already exists.

Not recommended: making the screen harder to use (slower scrolling, shrinking other apps' windows). It punishes a wrong call as much as a right one.

## Left out on purpose
Remembering places across sessions. A window title or page address saved to disk would break "sessions save counts, never text". The places live in memory and go with the session.

## Not verified
Raising a real window with Accessibility, switching real Safari or Chrome tabs, and how the ring and the dimmed edges look on a real display were not run: an agent cannot grant Accessibility, Automation or look at the screen. What was checked: the choice of place, the window matching, the AppleScript compiles in Safari's and Chrome's dictionaries (`osacompile`), the controller's behavior, the ring's timing and position math, and the menu rendered offscreen. A two-minute check for you: open two TextEdit documents and a Safari window with two tabs, start a session on a task that fits the first, drift to the second tab, then another app, and press Back to task. It should land on the first document, then the first tab.
