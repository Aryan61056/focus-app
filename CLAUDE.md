# focus-app (working name)

Native Mac and Windows focus app. The user states a task, a local AI compares the screen to it, nudges gently
when they drift, and escalates gently if they keep going. Projects carry context between sessions.
Everything runs on the device. Full detail: `docs/PLAN.md` (v0.5). Read the relevant section, don't copy it here.
Design context (register, personality, anti-references, principles) is in `PRODUCT.md`. Register: product. No DESIGN.md yet; it waits for spike S10.

"focus-app" is a neutral working name. The owner has not chosen a product name.

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
- **The notch is aesthetic, not functional (owner, 2026-10-01, replaces PLAN 4.6's nine functions).** It shows the ring, the task and the time, and expands only to a nudge or two buttons (Pause, Open app). Every function lives in the app window and the menu bar popover; none lives only in the notch.
- **The AI's decision is the hero (owner, 2026-10-01).** Today leads with "What Focus is reading" (window, call, one-line reason, how it decided), Review shows why each moment was flagged, Projects leads with a plain-language description plus an "Ask Focus about a window" box, and allow/never lists stay but sit in a collapsed, optional "Rules you set" section. Show the AI's work, but never overstate it: say it can be wrong and that not sure does nothing. Reasons are in memory only; Review keeps one until answered; sessions save counts, never text.
- **Default never-judged list (owner, 2026-10-01: "Yes go ahead").** Personal messaging apps (Messages, WhatsApp, Telegram, Signal), music players (Music, Spotify, Podcasts, Tidal, Pandora) and blank new-tab or start pages are not read, not sent to the model and not counted as off topic. A project allow or never rule still wins. Editable and switchable in Settings. In the brain, a window rule label of `unsure` means neutral evidence and no judge call.
- The no-timer session mode is named **Open**. Time budgets for messaging are optional and off by default.
- **Never overwhelm** (PLAN 4.8 calm rules and start flow) is a hard requirement for anything user-facing.

- **Judge model on Mac (owner, 2026-10-01): Apple's system model**, chosen for low memory and no download because the app runs in the background.
  The cost is accuracy (S1: about 71-79% strict precision, 57-67% recall on clear distractions with the two-judge rule). Safeguards must make up for it:
  rules and project context first, sustained agreement before any nudge, shadow mode, `unsure` does nothing. Qwen3-4B stays in the harness as a reference only.
  Windows needs its own runtime choice. Revisit if energy measurements (powermetrics) say otherwise.

## Decisions still the owner's (do not decide)
Product name, audience, pricing, open-sourcing the engine, minimum OS, Mac distribution, languages.
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
- **Ask first** before: installing toolchains (Rust, .NET, Xcode 27, a Python environment, Ollama), downloading any model
  (give name, source, size), sending data anywhere, pushing to a remote, publishing anything, accepting legal terms (the `fm` CLI license).
- Test data is synthetic. Never capture the owner's real screen. Never commit screenshots or model files (`.gitignore` blocks them).

## Marks in PLAN.md
- ✅ checked against docs or news on 2026-10-01. 🔍 unverified; a spike must confirm it before we build on it.
- "Starting target" numbers are guesses to tune against measurements.
- The feature catalog (section 5) skips the letter I. That is harmless.

## Machine
MacBook Pro M1 Pro, 16 GB, macOS 27.0, Xcode 26.6 (SDK 26.5), Swift 6.3.3, uv 0.11, system Python 3.9 (stdlib only for now).
Rust 1.99 installed via Homebrew rustup (owner approved 2026-10-01); use `export PATH="/opt/homebrew/opt/rustup/bin:$PATH"`. Not installed: .NET, Ollama, Xcode 27. No confirmed Windows PC.
Apple on-device model is reachable through the FoundationModels framework (Swift). The `fm` CLI is licensed (owner accepted the terms on 2026-10-01). The harness still uses the framework, which gives guided generation.

## Repo layout
- `docs/PLAN.md` the plan. `docs/S1-accuracy.md` the S1 results and recommendation.
- `eval/` S1 accuracy harness (scenarios, runner, Swift model helper, tests, results). See `eval/README.md`.
- `mac/` Swift package: `FocusJudge` (judge pipeline port), `FocusBrain` (state machine), `BrainTraces` and `brain-trace` (golden trace runner), `BrainSim` and `brain-sim` (episode simulator).
- `mac/Sources/FocusUI` the SwiftUI app views, controller and store; `FocusSense` real window sensing (Accessibility: app, title, page or file address; no window text yet; runs only during a session); `focus-sense-check` prints the Accessibility flag and the front app's name only.
- `core/brain-rs/` spike S5 part 1: the brain in Rust (no dependencies), same traces, differential-fuzzed against Swift. See `docs/S5-rust-brain.md`. The Swift brain stays the reference.
- `core/` shared across platforms: `prompts/` (single source of judge instructions), `traces/` (golden traces extracted from `docs/BRAIN-SPEC.md`). `tools/` generators and checks.
- `docs/BRAIN-SPEC.md` the brain spec (draft 0.1, written by a subagent, reviewed and implemented). `docs/EPISODE-SIM.md` simulated false nudges per session.
- `spikes/` the other spikes, one folder each (`spikes/s2-mac-capture/`, ...). Empty for now.

## Run and verify
```bash
python3 -m unittest discover -s eval/tests            # unit tests (metrics, rules, scenario validation)
python3 eval/run_eval.py --validate                   # validate and summarize scenario files
python3 eval/run_eval.py --backend oracle             # harness sanity: must score 100%
python3 eval/run_eval.py --backend fm_swift           # Apple system model, reports to eval/results/
python3 eval/run_eval.py --backend fm_swift --order relation --text-mode ocr   # other judge, OCR of synthetic screenshots
python3 eval/combine_results.py <run-a.json> <run-b.json>                      # two-judge rule from saved runs
python3 eval/run_eval.py --backend mlx_text --order relation                   # local Qwen text model (needs `uv sync` in eval/ and models in eval/.cache/models/)
python3 eval/run_eval.py --backend mlx_vlm --text-mode pixels                  # Qwen3-VL reading synthetic screenshots
python3 eval/measure_resources.py --backend mlx_text                           # memory/CPU/energy proxy; needs a quiet machine
(cd core/brain-rs && cargo run --offline -q --bin trace -- ../traces)          # golden traces against the Rust brain (PATH needs rustup, see Machine)
python3 tools/diff_brains.py --runs 400                                        # Swift vs Rust brain on random sessions
python3 tools/check_contrast.py                                                # WCAG contrast of the native color tokens, light and dark
./tools/build_app.sh                                                            # local ad-hoc-signed mac/.build/Focus.app (dev only, not for distribution)
(cd mac && swift run -q focus-sense-check)                                     # Accessibility allowed? and the front app's name (never a title)
(cd mac && swift test)                                                         # Swift judge port + brain (golden traces, scenarios, property tests)
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
