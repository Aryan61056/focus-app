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
- iOS lets no app see or block what you do in other apps. Only Apple's Screen Time API can, and that needs an entitlement we do not have on a free account.
  **So this does not stop you using your phone, and nothing in the app says it does.**
- What it does: keeps the task on the lock screen and Dynamic Island (Live Activity, system-drawn timers); lets you start, pause and end from the phone;
  and sends **one quiet reminder 45 s after you leave the app mid-session** ("Still on <task>?"), cancelled if you come back, at most one per 5 minutes,
  never during a pause, break, practice session or the last minute of a timed one. Past tense, never names a distraction.
- Next, if wanted: Screen Time shield (needs entitlement and a real iPhone), a Desk mode that keeps the phone face-up showing the ring.

## Decision needed (the owner's, not mine)
`CLAUDE.md` says "no network access in the engine". The engine (`FocusBrain`, `FocusJudge`, `FocusUI`, `FocusSense`) still has none, and
`tools/check_privacy.py` still passes on those modules; but `FocusLink` does listen on the local network when switched on. Please confirm that is acceptable
before merging, and keep the "do not claim" rules: nothing here supports "OS-enforced" or "cannot reach the network" copy.

## Verified and not
- Verified: `core/link` 21 tests incl. real loopback sockets; `FocusLinkBridgeTests` 8 tests (real controller, real PhoneLink, real client over a socket);
  full Mac suite, 0 failures; iPhone app 11 tests. Live: the built Mac app (throwaway store) and the iOS 27 simulator found each other over Bonjour,
  paired, kept the pairing across a relaunch, and a session started from the phone ran on the Mac.
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
