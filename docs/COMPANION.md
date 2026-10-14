# iPhone companion and the Mac link

Written 2026-10-13 by Claude with Aarav, and merged to main the same day at Aarav's request. **The Mac app's owner has not yet reviewed it**: please read "Decision needed" below and revert `mac/Sources/FocusLink` plus the FocusApp.swift lines if you disagree. It is off by default, so it does nothing until a user turns it on.

## What it is
- `companion/`: the iPhone app (SwiftUI, iOS 26, Liquid Glass). Today (ring and clock that follow the Mac; pause, break, +5 min, back to task,
  start a session), Insights (day, week chart, recent sessions), Mac tab (pairing, demo mode), and a Live Activity.
- `core/link/`: `FocusLinkKit`, the wire format and transport both apps use. Pure part (`FocusLinkWire`) and Network.framework part (`FocusLinkNet`).
- `mac/Sources/FocusLink/`: the Mac side. `PhoneLink` reads `SessionController` and calls its public actions; `PhoneLinkView` is the window
  (Session > iPhone...). **Off until the user turns it on.** Nothing listens or advertises while it is off.
- Touched in existing files: `mac/Package.swift` (one dependency, one target, one test target), `FocusApp.swift` (9 lines: import, one state
  property, `attach`, a Window scene, a menu item), `tools/build_app.sh` (two Info.plist keys for local network use).

## How the link works
- Direct over the local network (Bonjour `_focuslink._tcp`, TCP, peer-to-peer allowed). No accounts, no servers of ours, no internet.
- **Pairing:** the Mac shows an 80-bit code (16 characters). The phone proves it knows it with HMAC (the code is never sent) and the Mac then
  hands over a random 32-byte device key sealed under a key made from the code. Five wrong tries or five minutes close pairing.
- **Every later connection:** mutual HMAC challenge with that key (each side proves it holds it, with fresh nonces), then every frame is
  ChaCha20-Poly1305 with per-direction keys and counter nonces (replay, reorder and tampering fail to open). A 10 s handshake watchdog drops stalled connections.
- Keys: Keychain on the phone; `~/Library/Application Support/Focus/paired-phones.json` (mode 0600) on the Mac. Remove a phone in the iPhone window and it is refused from then on.
- What crosses: session state (phase, task name, clock, off-task time, how far the warning has climbed, practice flag, a short note) and insights
  (seconds, counts, task names the user typed, streak). **No window titles, no screen text, no pictures** (the store holds none).
- What the phone can ask: start, pause, resume, end, break, back to task, +minutes. All go through the same `SessionController` calls the Mac's own
  buttons use, and the Mac can refuse (for example, a second start). The brain is untouched.

## Accountability: what it does and does not do
- iOS lets no app see what you do in other apps. The one thing it allows is Apple's Screen Time API (Family Controls), which is how the Block tab works:
  the person picks apps, categories and websites in Apple's own picker, and Focus covers them with a system shield while a session is working
  (on task, unsure, drifting, recovering). They open again on a pause or break, when the session ends, in practice sessions, and never in demo mode.
  Focus only gets opaque tokens, so it never learns which apps were picked.
- **App guard (works on a free account):** the app offers one Shortcuts action, "Guard my session" (`companion/Sources/Intents`). The person makes one automation
  once in Shortcuts (App, Is Opened, their social apps, Run Immediately, then that action); iOS lets an app offer an action but not install an automation, so this setup cannot be pre-built.
  When a listed app opens, the action asks the Mac (waits up to 2 s) or, if it cannot be reached, trusts the last note if it is under 20 minutes old and a timed session has not run out
  (`GuardRules`), and if a session is working it brings Focus forward to a calm "Still working on" page (`GuardBounceView`). Otherwise it does nothing and the app opens normally.
  It cannot stop the other app from opening for a moment, and the person can switch it off ("Guard while I focus") or end it with "Take a break instead".
- **It is a promise to yourself, not a lock.** The person can lift it in the Block tab ("Open my apps now") or in Settings > Screen Time. Do not claim more.
- **Ending the block:** the phone app is asleep when a session ends on the Mac, so each block schedules a DeviceActivity interval; the monitor extension
  (`companion/Monitor`) clears the block at its end (timed session: its clock plus 2 minutes, at least 15 minutes because iOS refuses shorter; open session: 4 hours).
  Everything lives in one named store (`FocusShield`), so Focus never clears restrictions the person set up themselves. `companion/Shield` only sets the shield's wording.
- **Needs a paid Apple Developer team.** A free Personal Team cannot have the Family Controls capability. The simulator build always carries
  `App/ScreenTime.entitlements`; for a phone, build with `FOCUS_SCREEN_TIME_ENTITLEMENTS=App/ScreenTime.entitlements` (or set it in project.yml) once the team is paid.
  Without it the app still builds and runs, and the Block tab says Screen Time isn't available in this build. Shipping on the App Store needs Apple's approval of the entitlement.
- Also: the Live Activity, start/pause/end from the phone, and **one quiet reminder 45 s after you leave the app mid-session** ("Still on <task>?"), cancelled if you come back,
  at most one per 5 minutes, never during a pause, break, practice session or the last minute of a timed one. Past tense, never names a distraction.
- Next, if wanted: a Desk mode that keeps the phone face-up showing the ring; a shield button that returns to Focus.

## Decision needed (the owner's, not mine)
`CLAUDE.md` says "no network access in the engine". The engine (`FocusBrain`, `FocusJudge`, `FocusUI`, `FocusSense`) still has none, and
`tools/check_privacy.py` still passes on those modules; but `FocusLink` does listen on the local network when switched on. Please confirm that is acceptable
before merging, and keep the "do not claim" rules: nothing here supports "OS-enforced" or "cannot reach the network" copy.

## Verified and not
- Verified: `core/link` 21 tests incl. real loopback sockets; `FocusLinkBridgeTests` 8 tests (real controller, real PhoneLink, real client over a socket);
  full Mac suite, 0 failures; iPhone app 11 tests. Live: the built Mac app (throwaway store) and the iOS 27 simulator found each other over Bonjour,
  paired, kept the pairing across a relaunch, and a session started from the phone ran on the Mac.
- **App guard:** 6 rule tests (`GuardRulesTests`); the Block tab and the bounce page rendered in the iOS 27 simulator. **Not verified:** the automation firing, `continueInForeground(alwaysConfirm: false)` opening Focus without a prompt, the 2 s wait from a cold launch, and the cached-note fallback on a real phone.
- **Block tab:** 9 rule tests (`BlockRulesTests`) and the tab rendered in the iOS 27 simulator. **Not verified at all:** actual blocking, the picker, the Screen Time prompt, the monitor extension and the shield wording. The simulator has no Screen Time service, and the owner's team is a free Personal Team.
- **Not verified:** a real iPhone (everything so far is the simulator); Live Activity on a real lock screen and Dynamic Island; the pickup reminder firing;
  Local Network permission prompts on a real phone and on the Mac; typing the code by hand in the pairing screen (only the formatter is tested);
  behavior when the phone is backgrounded for long (iOS suspends it, so it reconnects when reopened); Reduce Motion, Dynamic Type extremes and VoiceOver by hand.
- Known limit: while the phone app is suspended it cannot update the Live Activity from the Mac; the timers keep counting, but a drift will not show until the app wakes.

## Run it
```bash
(cd core/link && swift test)
cd companion && xcodegen generate && open FocusCompanion.xcodeproj     # simulator, or set your Team to run on a phone
./tools/build_app.sh && open mac/.build/Focus.app                      # then Session > iPhone... > turn on > Pair a phone
# test without clicking: FOCUS_TEST_STORE=/tmp/ft FOCUS_LINK_PAIR_FILE=/tmp/code.txt   (Mac)   and   -pair <code> -remote-start "Task"   (phone, debug builds)
```
