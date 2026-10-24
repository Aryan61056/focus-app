# Hushd (repo and code still say focus-app)

Native Mac and Windows focus app. The user states a task, a local AI compares the screen to it, nudges gently
when they drift, and escalates gently if they keep going. Projects carry context between sessions.
Everything runs on the device. Full detail: `docs/PLAN.md` (v0.5). Read the relevant section, don't copy it here.
Design context (register, personality, anti-references, principles) is in `PRODUCT.md`. Register: product. No DESIGN.md yet; it waits for spike S10.

**Product name: Hushd (owner, 2026-10-24: "our new name is now Hushd"; the earlier name was Focus).** User-facing text, docs, the site and build output (Hushd.app, Hushd-<version>.dmg, "Hushd for iPhone.app") say Hushd. Deliberately NOT renamed, because they are saved on testers' Macs, matched across devices, or belong to the repo owner: bundle ids (`com.example.focus-app*`), the iCloud container, the Bonjour type `_focuslink._tcp`, the `focusapp://` URL scheme, the `~/Library/Application Support/Focus` data folder, Info.plist keys (`FocusBuildID`...), App Intent names, `FOCUS_*` env vars, the `focus_brain_*` FFI and Rust crate, Swift module and type names (`FocusUI`, `FocusButtonStyle`...), `Focus.entitlements`, the GitHub repo slug, and `eval/` measured data (Apple's "Focus mode" and the "Deep Focus" playlist titles are also left alone). Renaming modules and types is a separate PR so it does not collide with teammate commits. Screenshots in `site/assets` and the README image still show the old name until retaken.

## Who is who
- The owner (product owner) decides product questions. In PLAN.md, "you" means the owner and "I" means an earlier Claude.
- If PLAN.md and the owner's instructions conflict, the owner's instructions win. Say so.

## Decisions already made (do not reopen)
- On-device only. No cloud inference, no accounts, no telemetry, no network access for the engine.
- Native UI per OS: SwiftUI/AppKit on Mac, WinUI (C#) on Windows. Not Electron, Tauri or Flutter.
- Proposed shared core: a Rust "brain", a pure state machine `(state, event) -> (state, [effects])`.
  Spike S5 may overturn this. Fallback: two native implementations plus shared golden-trace tests.
- Default style is **Quiet** (calm, professional). The cat is an optional "Playful" pack, late in the roadmap. No mascot art now. No tomato.
- Mechanism and look are separate: the brain emits abstract effects, a style renders them (PLAN 7.1b).
- **Visual direction (owner, 2026-10-01): B "Lichen"** (`docs/design/b-lichen.*`). The product is a proper app window (sidebar, projects, history, insights, review, rules, settings) plus a light menu bar and notch presence. The owner wants it to convey the app's capability, even if it reads as a SaaS-style app.
- **Visual direction update (owner, 2026-10-16): "Workspace"**, replacing Lichen's look and the Droppy-match decoration (hero banners, gradient tiles). Three panes using the whole window: sidebar (places, projects as dots, settings pages), content, and a right "Hushd" panel ("What Hushd did": a short log of the AI's actions, Ask Hushd). Visual over text: rings, timelines, monospaced numbers, labels of a few words; "not too playful": neutral grays, one green accent, amber only for a slip, no colorful tiles, donuts or percentages. The AI must be apparent as support: a "Hushd reading <app>" bar with its three checks, the verdict, and the sparkle mark wherever the AI is at work. Keep "Hushd can be wrong. When it isn't sure, it does nothing." visible. Mockups were shown in chat on 2026-10-16.
- **Notch matches Droppy exactly (owner, 2026-10-24: "exact i mean exact same visuals to the droppy dynamic island", "drop the mini app feature", "glassy semi see through like ios 27", "every part should be animated").** Replaces the "slim, under about 420 pt" rule of 2026-10-16. Shape and layout are Droppy 16.0.1 measured from its window (rest 259x32 body, hover 285x35, open 485x196, shoulders 6/7/27.5, bottom corners 8.5/9/35, black for the top 61 percent then a see-through glass fade, a separate 29 pt glass tab pill 12.5 pt under the card). The Widgets page and everything behind it (`NotchWidget`, My line, their Settings groups and prefs) is gone, as is the dot field; pages are Home and Tray. Still true: no controls on the notch except "Back to task" on a nudge and the tab icons; the home page shows read-only figures where Droppy has transport buttons. Each piece of a page rises in on a staggered spring (`Rise`). Measurements and the capture recipe are in `docs/STATUS.md`.
- **The notch is aesthetic, not functional (owner, 2026-10-01, replaces PLAN 4.6's nine functions).** It shows the ring, the task and the time, and expands only to a nudge. **Since 2026-10-13 (owner) it has no controls except "Back to task" on a nudge:** no Pause, Resume, Open Hushd, Not now, Yes I am or break buttons, so it is never a way out of a nudge (a test fails if one comes back). Every function lives in the app window and the menu bar popover; none lives only in the notch.
- **The AI's decision is the hero (owner, 2026-10-01).** Today leads with "What Hushd is reading" (window, call, one-line reason, how it decided), Review shows why each moment was flagged, Projects leads with a plain-language description plus an "Ask Hushd about a window" box, and allow/never lists stay but sit in a collapsed, optional "Rules you set" section. Show the AI's work, but never overstate it: say it can be wrong and that not sure does nothing. Reasons are in memory only; Review keeps one until answered; sessions save counts, never text.
- **Default never-judged list (owner, 2026-10-01: "Yes go ahead").** Personal messaging apps (Messages, WhatsApp, Telegram, Signal), music players (Music, Spotify, Podcasts, Tidal, Pandora) and blank new-tab or start pages are not read, not sent to the model and not counted as off topic. A project allow or never rule still wins. Editable and switchable in Settings. In the brain, a window rule label of `unsure` means neutral evidence and no judge call.
- **Screen reading (owner, 2026-10-01: "Implement the screenshot analyzing functionality").** An opt-in switch (Settings, or Today) takes a picture of the front window every 3 s during a session (ScreenCaptureKit, needs Screen Recording), shows it on Today, reads its words with Apple Vision OCR every 8 s, and adds them to the judge's next check as window text. The model sees words, never the picture. Pictures and words live in memory only, are dropped on window change and session end, skip private and never-judged windows, and are dropped (not judged) if they contain login or payment words. Unverified on a real display: an agent cannot grant Screen Recording. The S1 OCR-of-synthetic-screenshots path measured 88% strict precision on 8 flags and 47% recall; real windows are noisier.
- **Matching-words rule (Claude, 2026-10-02, owner can reverse; Settings switch):** a window sharing a distinctive word with the task or project text counts as on task without the model, except on feeds, video and news. Quiet by construction. See `docs/STATUS.md`.
- **Friends (owner, 2026-10-16: "Yea build it").** A social page with a weekly board, cheers and emoji avatars, the one exception to on-device only: after the user turns sharing on, the chosen name and avatar and daily totals (time on task, slips, sessions, streak) go to invited friends through iCloud (CloudKit sharing, no accounts or server of ours). Never task, app, site, window or screen text. Off by default; off deletes it. CloudKit lives only in `FocusSocial`. The Friends page is the one exception to "not too playful" (owner: "a lot more fun than analytical"), but stays grown-up with little text: explanations go behind info buttons (owner: "not for kids", "not too much text"). There, "Hushd can be wrong" stays behind the info button by the board switch, not on the page (owner, 2026-10-16). See `docs/SOCIAL.md`. Unverified against real iCloud.
- **iPhone sync over iCloud (owner, 2026-10-16: "implement iCloud sync between the mobile and desktop app").** The Mac keeps the phone's Insights numbers and typed task names in the user's own private iCloud, so the phone shows them when the Mac is off or away; one way, Mac to phone; off by default; off deletes it. Live session control stays on the local link. CloudKit lives only in `core/link` `FocusLinkCloud`. See `docs/ICLOUD-SYNC.md`. Unverified against real iCloud.
- **Back to task goes to the place (owner, 2026-10-16: "get them to the correct area").** It returns to the window, tab or document you were working in (the one you settled in, else the one you spent the most time in), not only the app, and says where in a tooltip and the menu. Places are memory only: window titles and addresses are never saved (counts only), and they go with the session. New optional cues (the landing ring, the closing edges) are Settings switches; ideas not built are in `docs/NUDGE-IDEAS.md`.
- **Next step removed (owner, 2026-10-17: "that feature should be removed bc it seems like bloat").** No prompt, field or widget asks for a next step; do not bring one back. Prefer cues that need no typing. Back to task grew (reopen, tabs in any app, working set, spot, key, link, Dock, put-away) and gained off-by-default cues (beacon, window-only gray, fog, pointer ring, sound); see `docs/NUDGE-IDEAS.md` and the last section of `docs/STATUS.md`. All unverified on real windows and audio.
- **Start form and iPhone (owner, 2026-10-17).** The sidebar "Add iPhone" card is gone (the iPhone window opens from the toolbar, the menu bar and Session > iPhone). The start form has no 5 min / 25 / Until / Open buttons: one slider with stops (fine at the short end, Open at the far end) that starts on the person's usual timed length once they have a habit, else Open; "Until a time..." is a small link. The iPhone window can install the iPhone app on a plugged-in phone through Xcode's `devicectl` (needs a build embedded by `tools/build_iphone.sh`; unverified on a real phone). See `docs/STATUS.md`.
- **Beta testing system (owner, 2026-10-18: "build an end to end beta testing system for users", "accounts can be on the bottom left", "I don't have TestFlight").** Builds go to testers as a DMG by hand (AirDrop, a shared folder, a message), never TestFlight. Feedback comes back as a file the tester previews and saves; Hushd sends nothing, and a report holds counts, settings switches and the tester's own words, never task or project names, titles, addresses, screen words or pictures. The bottom-left "account" is a **local profile** (name and avatar shared with Friends, build tag, feedback), not a sign-in: real accounts would reverse "no accounts" and are the owner's call. Detail: `docs/BETA.md`; tools in `tools/beta/`; tester pages in `docs/beta/`.
- **Beta on GitHub (owner, 2026-10-19: "improve the github so it allows users to start beta testing", "do everything end to end", "add features to beta testing too").** Betas are public GitHub pre-releases (`tools/beta/publish.sh`), the README is the tester's front door, and feedback comes back as GitHub issues (forms in `.github/ISSUE_TEMPLATE`, label `beta`) with the report file dragged in by the tester; `tools/beta/feedback.py pull` collects them. Hushd opens only `https://github.com` pages, on a click, with nothing but the build in the address. Reports may carry Hushd's recent calls as on/unsure/off and how it decided, never the window. A DMG handed out by hand still works. Detail: `docs/BETA.md`.
- The no-timer session mode is named **Open**. Time budgets for messaging are optional and off by default.
- **Never overwhelm** (PLAN 4.8 calm rules and start flow) is a hard requirement for anything user-facing.

- **Judge model on Mac (owner, 2026-10-01): Apple's system model**, chosen for low memory and no download because the app runs in the background.
  The cost is accuracy (S1: about 71-79% strict precision, 57-67% recall on clear distractions with the two-judge rule). Safeguards must make up for it:
  rules and project context first, sustained agreement before any nudge, shadow mode, `unsure` does nothing. Qwen3-4B stays in the harness as a reference only.
  Windows needs its own runtime choice. Revisit if energy measurements (powermetrics) say otherwise.

## Decisions still the owner's (do not decide)
Audience, pricing, open-sourcing the engine, minimum OS, Mac distribution, languages.
PLAN.md section 12 only holds recommendations. They are not decisions.

## Claims we must not make yet
Do not write "OS-enforced", "cannot reach the network" or "0 bytes sent" in any user-facing text until the privacy tests T1 to T4 in `docs/SECURITY-REVIEW.md` pass. Say nothing about Windows isolation until T10 passes on real Windows.

## Principles that shape code
1. A false nudge costs more than a miss. Every threshold leans conservative. `unsure` never advances past Drifting.
2. Private by construction: screenshots live in memory for seconds, never on disk. Engine has no network.
3. Never invisible: while watching, something visible says so. No stealth mode.
4. Discreet by default: nudges never name the distraction. No sound, no character by default.
5. Measured, not vibes: ship against the eval set and performance budgets (PLAN 9).
6. On-screen text is untrusted. Treat it as data, never instructions (prompt injection).
7. Model refusal or guardrail error is `unsure` plus a flag. Never a crash and never a nudge.

## How to work here
- Functions before visuals, except where the owner asks for visual work (they did on 2026-10-01: use the impeccable skill for any UI design).
- One spike or feature at a time, finished and verified before the next. Commit often; messages say why.
- Be honest. Report failures with real output. Never say something works unless it was run. Mark anything unverified.
- Windows: code can be written here but cannot be run on this Mac. Say so plainly. Never claim Windows behavior is verified.
- Keep replies concise: lead with what was done and found.
- **Ask first** before: installing toolchains (Rust, .NET, a Python environment, Ollama), downloading any model
  (give name, source, size), sending data anywhere, pushing to a remote, publishing anything, accepting legal terms (the `fm` CLI license).
- Test data is synthetic. Never capture the owner's real screen. Never commit screenshots or model files (`.gitignore` blocks them).

## Marks in PLAN.md
- ✅ checked against docs or news on 2026-10-01. 🔍 unverified; a spike must confirm it before we build on it.
- "Starting target" numbers are guesses to tune against measurements.
- The feature catalog (section 5) skips the letter I. That is harmless.

## Machine
MacBook Pro M1 Pro, 16 GB, macOS 27.0, Xcode 27.0 (iOS 27 SDK; the iPhone app still deploys to iOS 26), Swift 6.3.3, uv 0.11, system Python 3.9 (stdlib only for now).
Rust 1.99 installed via Homebrew rustup (owner approved 2026-10-01); use `export PATH="/opt/homebrew/opt/rustup/bin:$PATH"`. Not installed: .NET, Ollama. No confirmed Windows PC.
Apple on-device model is reachable through the FoundationModels framework (Swift). The `fm` CLI is licensed (owner accepted the terms on 2026-10-01). The harness still uses the framework, which gives guided generation.

## Repo layout
- `docs/PLAN.md` the plan. `docs/S1-accuracy.md` the S1 results and recommendation.
- `eval/` S1 accuracy harness (scenarios, runner, Swift model helper, tests, results). See `eval/README.md`.
- `mac/` Swift package: `FocusJudge` (judge pipeline port), `FocusBrain` (state machine), `BrainTraces` and `brain-trace` (golden trace runner), `BrainSim` and `brain-sim` (episode simulator).
- `mac/Sources/FocusUI` the SwiftUI app views, controller and store; `FocusSense` senses, all running only during a session: window (Accessibility: app, title, page or file address), idle/sleep/lock/low-power signals to the brain (`SystemWatcher`), and opt-in screen reading (`PreviewWatcher`: ScreenCaptureKit picture + Vision OCR words, memory only); `focus-sense-check` prints the Accessibility flag and the front app's name only.
- `core/brain-rs/` spike S5: the brain in Rust (no dependencies) with a hand-written C ABI, same traces, differential-fuzzed against Swift and called from Swift (`brain-ffi-check`). Windows half untested. See `docs/S5-rust-brain.md`. The Swift brain stays the reference.
- `mac/Sources/FocusSocial` friends over iCloud (CloudKit), the only networking for friends; `FocusUI/Social` the friends model, store and `FriendsTransport` protocol.
- `mac/Sources/FocusUI/Beta` the beta: build info, local event journal, crash and hang reading, feedback report; `Views/BetaViews.swift` the profile chip, feedback sheet and Settings > Beta; `tools/beta/` release, publish, feedback triage and roster scripts; `beta/` notes, known issues and build counter; `.github/ISSUE_TEMPLATE/` the beta issue forms.
- `core/` shared across platforms: `prompts/` (single source of judge instructions), `traces/` (golden traces extracted from `docs/BRAIN-SPEC.md`). `tools/` generators and checks.
- `docs/BRAIN-SPEC.md` the brain spec (draft 0.1, written by a subagent, reviewed and implemented). `docs/EPISODE-SIM.md` simulated false nudges per session.
- `spikes/` the other spikes, one folder each (`spikes/s2-mac-capture/`, ...). Empty for now.

## Run and verify
```bash
python3 -m unittest discover -s eval/tests            # unit tests (metrics, rules, scenario validation)
python3 eval/run_eval.py --validate                   # validate and summarize scenario files
python3 eval/run_eval.py --backend oracle             # harness sanity: 100% except the 2 scenarios the injection guard withholds (95% recall); it rewrites eval/results/oracle_full_rules.*, so git checkout those after
python3 eval/run_eval.py --backend fm_swift           # Apple system model, reports to eval/results/
python3 eval/run_eval.py --backend fm_swift --order relation --text-mode ocr   # other judge, OCR of synthetic screenshots
python3 eval/combine_results.py <run-a.json> <run-b.json>                      # two-judge rule from saved runs
python3 eval/run_eval.py --backend mlx_text --order relation                   # local Qwen text model (needs `uv sync` in eval/ and models in eval/.cache/models/)
python3 eval/run_eval.py --backend mlx_vlm --text-mode pixels                  # Qwen3-VL reading synthetic screenshots
python3 eval/measure_resources.py --backend mlx_text                           # memory/CPU/energy proxy; needs a quiet machine
(cd core/brain-rs && cargo run --offline -q --bin trace -- ../traces)          # golden traces against the Rust brain (PATH needs rustup, see Machine)
(cd mac && swift run -q brain-ffi-check ../core/traces)                         # Swift calling the Rust brain over its C ABI (build core/brain-rs --release first)
python3 tools/diff_brains.py --runs 400                                        # Swift vs Rust brain on random sessions
python3 tools/check_contrast.py                                                # WCAG contrast of the native color tokens, light and dark
./tools/check_notch_hover.sh                                                    # moves the real pointer onto the notch area; fails if the demo app crashes (needs the bundle built)
open -n --env FOCUS_TEST_STORE="$TMPDIR/focus-test" mac/.build/Hushd.app                                # real sensing and judge, throwaway store and settings (use this when driving the app with computer control)
open -n --env FOCUS_DEMO=1 [--env FOCUS_DEMO_NOSESSION=1] [--env FOCUS_DEMO_ACTIONS=section:settings,start] --env FOCUS_SELFSHOT=/tmp/shots mac/.build/Hushd.app   # demo app renders its own windows (main window, notch panel) to PNGs after 12 s, then quits; no screen capture, no permission
# Quiet renders (nothing on the owner's screen): add --env FOCUS_SELFSHOT_QUIET=1 and launch with `open -g -n` (window sits under the desktop picture, no focus taken); FOCUS_SELFSHOT_SIZE=760x520 sets the window size, FOCUS_DEMO_ACTIONS accepts `sidebar`.
# Do it from a COPY of Hushd.app whose CFBundleIdentifier is changed and re-signed ad hoc: a render saves the window size and sidebar width, and with the real bundle id they land in the owner's own settings.
./tools/build_app.sh                                                            # local ad-hoc-signed mac/.build/Hushd.app (dev bundle)
./tools/build_dmg.sh                                                            # mac/.build/Hushd-<version>.dmg: app + Applications shortcut, checked after it is built; ad-hoc signed and not notarized unless the owner supplies a Developer ID (see the script header)
(cd mac && swift run -q focus-sense-check)                                     # Accessibility allowed? and the front app's name (never a title)
(cd mac && swift test)                                                         # Swift judge port + brain (golden traces, scenarios, property tests)
./tools/check_space_scripts.sh                                                  # Arc and Dia scripts' logic against stand-in apps (no permission prompt; not the real browsers)
./tools/check_space_browsers.sh                                                 # read-only check against the real Arc and Dia (you allow Automation once; prints only space or profile)
(cd mac && swift run -q focus-snapshot /tmp/shots --start)                      # the start sheet, offscreen (no screen capture, no permission)
python3 -m unittest discover -s tools/beta -p 'test_*.py'                     # beta feedback triage and roster tools
tools/beta/release.sh --dry-run                                                # what the next beta would be (docs/BETA.md); without --dry-run it builds a DMG
tools/beta/publish.sh <version>-beta.<n> --dry-run                             # checks a built beta and prints its GitHub release text; without --dry-run it PUBLISHES (ask first)
(cd mac && swift run -q focus-snapshot /tmp/shots --beta)                      # every beta surface offscreen, light and dark
python3 tools/check_privacy.py                                                 # source scan: no networking, URL opening, logging or non-system model in engine modules (does not lift the claims ban)
python3 tools/check_parity.py                                                  # Swift judge pipeline vs Python harness, all 100 scenarios
(cd mac && swift run -q brain-trace ../core/traces)                            # golden traces against the Swift brain
python3 eval/export_verdicts.py && (cd mac && swift build -c release && .build/release/brain-sim --verdicts ../eval/results/verdicts_two_judge.json)   # episode simulator, docs/EPISODE-SIM.md
```
Gotcha: Xcode's `python3` shim exports `SDKROOT` for the Command Line Tools SDK, which is newer than the compiler.
`eval/focus_eval/backends.py` clears it before calling `swiftc`. Do the same for any new Swift helper started from Python.
Results are written to `eval/results/*.md` and `.json`. Compare runs by reading those files, not memory.

## Eval conventions (S1)
- Scenarios are JSON in `eval/scenarios/` (dev set, used for tuning) and `eval/scenarios_heldout/` (run rarely, after a prompt is frozen).
- Labels: `on_task`, `unsure`, `off_task`. Difficulty: `clear` or `gray`. Gold labels encode product policy, written in `eval/README.md`.
- Headline metric is off-task precision, strict (a gold `unsure` predicted `off_task` counts as a false nudge), with a Wilson interval.
  With about 20 off-task moments, no run can statistically certify 97%. Say so whenever quoting a number.
- Per-moment metrics are not per-episode metrics. "False nudges per 3 hours" needs sequences and the brain's smoothing.
- Do not tune on the held-out set. If a prompt changes after a held-out run, the held-out set is spent and needs fresh scenarios.

## Code conventions
- Python: stdlib only unless the owner approves an environment. Python 3.9 compatible (`from __future__ import annotations`, no `match`).
- Swift: compile helpers with `swiftc` from the installed Xcode. Output goes to gitignored `.build/`.
- Short comments that say why. Match surrounding style.
- UI copy (later): calm, brief, second person, sentence case, no jargon, no exclamation marks, never name the distraction (PLAN 4.12).
