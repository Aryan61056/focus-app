> **Provenance.** Written by a subagent (read-only, nothing run). The first session that used it checked three code claims by reading: title and URL sat outside the untrusted prompt block, `</window_text>` in screen text could close the block, and the MLX helpers claimed to never touch the network while only setting `HF_HUB_OFFLINE`. All three were real. The first two are fixed in `eval/focus_eval/prompts.py` (the other 400 prompts are byte-identical, so S1 results stand); the helper comments now say the process is not network-isolated. Everything about Apple, Windows and sandbox behavior remains unverified until tests T1 to T4 and T10 run.
>
> **Until T1 to T4 pass, do not say "OS-enforced", "cannot reach the network" or "0 bytes sent" in any user-facing text.**

# Security and privacy review (read-only)

Date: 2026-10-01 · Scope: `docs/PLAN.md` v0.5 (sections 2, 3, 4.10, 5, 7, 8.2, 9.2, 11, 12), `CLAUDE.md`, `PRODUCT.md`,
`docs/S1-accuracy.md`, and all code in `eval/` (`focus_eval/`, `swift/`, `mlx/`, runners, result files, `.cache/` listing).
Method: reading only. Nothing was built, run, installed or fetched. No vendor documentation was read for this review,
so every statement about Apple or Microsoft behavior below is marked **unverified** unless it comes from this repo's own measurements.

**Basis codes in the table.** `R` = verified by reading this repo (path:line given). `I` = my inference from the design.
`U` = depends on Apple or Microsoft behavior I have not verified. `T` = needs a test on a real machine (section 3).

Severity reflects the harm if the plan ships as written. Almost nothing product-side is built, so most findings are plan findings
and are cheap to fix now.

---

## 1. Top 5 issues

**1. The network boundary is drawn around the wrong set of processes (high).**
The headline says "the process that sees your screen cannot reach the internet" (PLAN 2, line 50). But screen-derived data does not
stay in the engine: window titles, URLs, model reasons, learned rules, the verdict history and the *Why?* text all reach the app
process, which holds the brain and database (7.1, line 631; 7.5) and runs Sparkle updates, so it has network access (7.6, line 721).
The Screen Recording and Accessibility grants are probably attributed to the app, not the helper (7.2 already marks this 🔍).
Titles-and-text mode needs Accessibility, and reading other apps through Accessibility from inside App Sandbox is widely reported
not to work (unverified). So the mode sold as the most private one may be the one whose reader cannot be sandboxed.
And a sandboxed engine without `network.client` can probably still cause network traffic through other processes: opening a URL
in the browser, a shared container that the downloader reads, or a downloader that accepts arbitrary URLs.
*Fix:* define the invariant as "every process that receives screen-derived data has no network entitlement, and the only
network-capable processes (updater, downloader) accept nothing but a fixed model ID." Move Sparkle into its own data-free
process, or make the app process network-free. Spike S6 runs the egress matrix (T1), the TCC attribution test (T2) and the
Accessibility-from-sandbox test (T3) before any claim is written.

**2. Apple's model runs outside our sandbox, and what it does with prompts is unverified (high).**
This repo's own measurement shows inference in a system process ("TGOnDeviceInfere…", about 458 MB during calls;
`eval/results/resources_fm_swift-relation.json`, `docs/S1-accuracy.md:93`). Window text therefore leaves our sandboxed process
for an Apple-controlled daemon that our entitlements do not constrain. Whether any FoundationModels path can reach
Private Cloud Compute or another server, whether prompts can appear in logs, sysdiagnose or analytics, and whether guardrail
checks are local: all unverified. macOS 27's pluggable `LanguageModel` protocol (7.4, line 703) also means a future code
change could quietly swap in a backend that is not on-device.
*Fix:* word the claim as "processed by Apple's on-device model in a macOS system process". Use only `SystemLanguageModel.default`
and add a CI check that rejects any other `LanguageModel` conformer. Run T4 (network off, canary grep of logs).

**3. Prompt-injection handling covers only the page body, and stored injection is not considered (medium-high).**
Only `<window_text>` is declared untrusted (`eval/focus_eval/prompts.py:23,43`). App name, title, URL and document path go into the
prompt as plain lines (`prompts.py:66-71`), and any web page sets its own title and URL path. The body is inserted unescaped, so text
containing `</window_text>` ends the block early (`prompts.py:73-76`). Truncation at 1,200 characters (`prompts.py:8,75`)
lets an attacker put the injection first. The plan also turns untrusted text into trusted context that the model reads on every
call: the context card (4.10), paste-to-set-up drafted by the model from third-party briefs (A10, line 343), and
"I'll keep what I've learned" (line 267). The test set has only 4 injection moments, all in the body and none with a
no-injection twin. Apple's relation judge returned `neutral` (so `unsure`) for both injected clear distractions (adv-01 and
h-adv-01, in both the full-text and OCR runs), while Qwen flagged them. I cannot tell whether the injection caused this.
*Fix:* see F13 to F19. Run T7 (paired injection suite with a flip-rate gate).

**4. The anti-stalkerware guardrails cannot be enforced as written (high).**
The only guardrail is "always-visible indicator, no remote features" (3.9, 9.2). But the plan itself notes that new Windows tray
icons start in the overflow flyout (8.1, line 741) and that the macOS 27 menu bar has an overflow (line 770). Windows needs no
permission prompt for capture or UI Automation (9.2, line 810). Silent install and MDM profiles (G9), launch at login, schedules
(line 861) and calendar auto-start (line 597) let a third party deploy a watcher the user never started. History and CSV export
(E5) give anyone with the unlocked session a 30-day log of apps and domains. App Intents, automation hooks, the CLI (A7) and
exports to synced folders are remote channels in practice.
*Fix:* see F32 to F35. Run the red-team test T11.

**5. Data at rest and crash paths contradict "no window text stored" and "screenshots never on disk" (medium-high).**
The verdict timeline stores the model's short reason (7.5), and the relation judge's `topic` field is literally a summary of the
window content (`eval/swift/fmjudge/main.swift:56-57`), so derived window text lands on disk alongside a browsing history.
Crash dumps have no mechanism behind them (9.2, line 801, 🔍). On Windows, Error Reporting heap dumps could carry screenshot
buffers to Microsoft under default consent (unverified). In the harness, result files containing titles and reasons are tracked
in git (`eval/run_eval.py:79-82`). The planned dogfood recorder would save real window text and downscaled screenshots (9.3,
line 816) with no storage rules and no gitignore entry for JSON results.
*Fix:* see F25 to F30. Run the canary sweeps T5 and T6.

---

## 2. Findings

| # | Sev | Plan/Code | Finding | Evidence | Fix or resolving spike | Basis |
|---|---|---|---|---|---|---|
| **Process isolation (Mac)** | | | | | | |
| F1 | High | Plan | Screen-derived data (titles, URLs, reasons, *Why?* text, rules, history) reaches the app process, which has network for Sparkle. "Engine has no network" ≠ "the process that sees your screen cannot reach the internet". | PLAN 2 l.50, 7.1 l.631, 7.2 l.656-660, 7.6 l.721, G4 l.485 | Make every data-bearing process network-free. Put Sparkle in a separate process that receives no data. Rewrite the 2.1 claim to match whatever S6 proves. | R, I |
| F2 | High | Plan | A missing `network.client` entitlement blocks sockets, not egress. A sandboxed engine can probably still open a URL in the browser (data in the query string), write to a shared container, or pass strings to a network-capable peer. | 7.2 l.658, S6 l.843 ("cannot connect" is the only criterion) | Widen S6's success criterion from "cannot connect" to "cannot cause egress". Run T1. Engine code may not link NSWorkspace URL opening or the pasteboard. | I, T |
| F3 | High | Plan | If the downloader accepts a URL or any free text over IPC, it becomes a proxy: engine → app → downloader "fetch https://x/?q=…". | 7.2 l.658, G3 l.484 | The downloader accepts only a model ID. URLs and hosts are compiled in, requests carry no query data, and the downloader never reads files the engine writes. | I |
| F4 | High | Plan | TCC attribution: when capture lives in a helper, Screen Recording and Accessibility grants are probably attributed to the responsible app. The network-capable app would then hold capture rights too. | 7.2 l.658 (marked 🔍) | Run T2 in S2/S6. If the app holds the grant, the app must be network-free (F1), or the claim changes. | U, T |
| F5 | High | Plan | Titles-and-text mode needs Accessibility (B14 l.366). Reading other apps through AX from a sandboxed process is widely reported not to work. Browser URLs through Apple Events need automation entitlements. The "no pixels" mode may therefore get the weakest isolation. | 8.2 l.762-763, G8 | Add T3 to S7. If AX needs an unsandboxed reader, that reader must link no networking code and pass a deny test, and the claim must say "not OS-enforced" for this mode. | U, T |
| F6 | High | Plan | No IPC client validation is planned. If the engine is a launchd agent or Mach service, as login items usually are, any local process could request verdicts, *Why?* text or captures. That is a TCC confused deputy. | 7.2 l.660 (says only "small structured messages") | Prefer a bundle-private XPC service. Otherwise check the peer's code-signing requirement on every connection. On Windows, ACL the pipe to the package SID and verify the client signature. Run T9. | I |
| F7 | Medium | Plan | A user can check Mac entitlements with `codesign -d --entitlements -`. That is the strongest user-checkable proof available, and the verification guide does not mention it. | G5 l.486, G7 l.488 | Publish expected entitlements per binary and the exact command. | I |
| **Apple frameworks** | | | | | | |
| F8 | High | Code+Plan | FoundationModels inference ran in a system daemon, not our process. Prompts (window text) cross into Apple's process. PCC or server fallback, prompt logging and local guardrails: all unverified. The pluggable `LanguageModel` protocol makes a non-local backend a one-line change. | `resources_fm_swift-relation.json` (TGOnDeviceInfere, 458 MB), S1 l.93, 7.4 l.703, `fmjudge/main.swift:87` | Scope the claim to Apple's on-device model. CI rejects any model other than `SystemLanguageModel.default`. Run T4. | R, U, T |
| F9 | Low | Code+Plan | Vision OCR (`shotgen/main.swift:56-66`) and NLEmbedding (`embed/main.swift:7`) are assumed to be on-device. Any asset downloads would happen in system daemons that users cannot attribute. Apple can also change the system model in an OS update, so verdicts and refusals can shift without notice. | as cited | Note the OS build and model version in every result and log. Rerun S1 after OS updates. Include Vision and NLEmbedding in T4. | U |
| **Windows** | | | | | | |
| F10 | High | Plan | Windows isolation is entirely unverified. AppContainer without `internetClient` is the known mechanism, but capture and UI Automation from a low-integrity container may be blocked or need restricted capabilities. I did not check the Build 2026 "execution-container SDK" claim. The fallback firewall script is policy, not construction: admins can remove it, and a path rule may not cover child processes. | 7.2 l.659, 8.2 l.761-762 | S6-W on real hardware (T10). Until it passes, Windows copy must not say "private by construction". | U, T |
| F11 | Medium | Plan | Windows ML downloads execution providers at runtime, so executable code enters the inference path from the network. This conflicts with a no-network engine and with our own hash pinning. | 7.4 l.705 | Find which process fetches the providers and whether they can be pre-staged and signature-checked. Part of S6-W. | R, U |
| F12 | High (Win) | Plan | Windows Error Reporting can collect dumps that include heap memory and upload them under default consent (unverified). Capture buffers and window text would then leave through the OS. The plan's "disable crash dumps" has no mechanism. | 9.2 l.801 | Exclude the engine from WER, or exclude buffers with the WER exclusion APIs (names unverified). Zero buffers after use. Run T6. | U, T |
| **Prompt injection** | | | | | | |
| F13 | Medium | Code | App, title, URL and document path are screen-controlled but sit outside the untrusted block. The instructions call only `<window_text>` untrusted. | `prompts.py:23,43,66-71` | Put every screen-derived field in one delimited block that is declared untrusted. Keep only the task and user-typed context outside it. | R |
| F14 | Medium | Code | Delimiter break-out: the body is inserted raw, so `</window_text>` followed by `Task: …` escapes the block. The 1,200-character head truncation favors an attacker who writes first. | `prompts.py:8,73-76` | Escape or strip delimiter tokens. Use a random per-call nonce tag. Sample text from several regions, not just the head. | R |
| F15 | Medium | Code | Injection coverage is 4 moments, all in the body, with no control twins. The Apple relation judge downgraded both injected clear distractions to `unsure` (dev full and OCR runs, held-out). The cause is unknown. | `scenarios/adversarial_misc.json` (adv-01, adv-02), `scenarios_heldout/…` (h-adv-01, h-adv-02), `results/fm_swift-relation_*` | Paired scenarios (the same page with and without injection) for every field, plus break-out and padding cases. Report flip rate. Gate: zero flips toward `off_task`. Run T7. | R (results), I (cause) |
| F16 | Medium | Code | `mlx_judge.parse` takes the first non-greedy `{…}` anywhere in the output. Screen JSON echoed by the model wins, and nested braces break parsing. The same pattern would be dangerous in a Windows llama.cpp path. | `mlx/mlx_judge.py:30-34` (unknown relations already map to `unsure`, `backends.py:143`: good) | Constrained decoding (a grammar, or Windows Structured JSON Output) plus a strict whole-output parse. | R |
| F17 | Medium | Plan | Stored injection: the context card is read on every judgment, paste-to-set-up has the model draft the profile from third-party text, and project offers keep "what I've learned". One poisoned page or brief persists across sessions. | 4.10 l.265, l.267; A10 l.343 | Context and profile text only from user-typed text or text the user confirmed in a shown diff. Never learn from window text. Label model-drafted text. | R, I |
| F18 | Medium | Plan+Code | The model's `reason` is attacker-influenced free text. It is shown in trusted UI (*Why?*, Show reasons) and stored. "Must not repeat instructions" is a request to the model, not a check. | `prompts.py:25,44`; G4 l.485; C9; 7.5 | Render reasons from category or relation templates, or filter them in code: no URLs, no imperatives, a hard word cap. Label them as the model's guess. | R, I |
| F19 | Low | Plan | What an attacker can force: suppression is worth little (the user can pause). False nudges on legitimate pages (a colleague's doc, ticket or chat message) defeat "sustained agreement" because the page persists. Corrections become rules (B9), and a broad rule can over-allow. | B5, B9 l.361, 3.6 | "This is relevant" pins that page for the session. Rules are scoped to host plus path by default and shown as receipts. A page that looks like an injection downgrades verdicts to `unsure`. | I |
| F20 | Medium | Plan | The protocol link and CLI (A7) let any web page or local process start a session or set the task. That enables task gaming and watching the user never started. | A7 l.340, A3 l.336 | A link only opens a prefilled start sheet, and a click is required. Neither the CLI nor App Intents can change the task mid-session or read history or *Why?* text. | I |
| **Supply chain** | | | | | | |
| F21 | Medium | Plan | "Hash-pinned, signed manifest" is unspecified: key custody, rotation, what gets hashed. Tokenizers and chat templates (`chat_template.jinja` ships with the model) control prompt assembly. GGUF and ONNX parsers are memory-unsafe code inside the process that sees the screen. | 7.4 l.708, 9.2 l.804, `eval/.cache/models/*/chat_template.jinja` | Embed the manifest in the signed app bundle, so code signing is the signature. Hash every file, templates included. The engine verifies at load from a read-only location. Prefer safetensors and fuzz the loaders. Run T8. | R, I |
| F22 | Medium | Code | The harness helpers that first handle window text run with full network access. `uv run` may resolve and sync from PyPI at start, and `HF_HUB_OFFLINE` covers only the HF hub. The comments "Never touches the network" are not enforced. | `backends.py:175-177,198-200`; `mlx_judge.py:7`; `fmjudge/main.swift:5` | Use `uv run --offline --frozen` (verify the flags) and run the helpers under a deny-network sandbox profile. That doubles as the S6 prototype. | R, I |
| F23 | Low | Code | Model provenance in the harness is repo@commit only, with no per-file hashes. S1 says "verified files" without recording how they were verified. | `eval/.cache/models/*/SOURCE.txt`, S1 l.59 | Record a sha256 per file and check it at load. | R |
| F24 | Low | Plan | Update checks and model downloads are network traffic from the product (IP, version, timing, hardware tier). "Nothing leaves the device" needs that qualifier. | 7.6 l.721, G3 | Qualify the copy. No system profiling in update checks. Offer an offline model install. | R |
| **Data at rest, crashes, logs** | | | | | | |
| F25 | Medium | Plan+Code | The verdict timeline stores model reasons (and possibly `topic`, a summary of the content) plus app or domain and a timestamp for 30 days. That is derived window text and a browsing history. | 7.5 l.712, `fmjudge/main.swift:56-57`, E5 l.451 | Store only the category enum and app or domain by default. Keep reasons in memory. Durations-only (as in J15) for anyone who wants it. | R |
| F26 | Medium | Plan | There is no logging policy. Unified log and ETW entries containing titles or URLs persist and end up in sysdiagnose or support bundles. | absent from 9.2 | Rule: never log screen-derived strings. Logger privacy defaults to private, and CI flags `.public` on screen-derived values. Run T5. | I |
| F27 | Medium | Plan | Mac crash reports are believed to hold stacks, not heap (unverified). Swap, the Windows pagefile and hibernation files can hold capture buffers. Any diagnostics export (G2) must be checked. | 9.2 l.801, G2 l.483 | Zero buffers right after inference, keep them small, and run the canary crash test T6 on both OSs. | U, T |
| F28 | Medium | Code+Plan | Result JSON and MD files record titles and model reasons and are tracked in git. The planned dogfood recorder keeps real window text and screenshots, which conflicts with G1 for dogfood builds. Nothing separates real data from synthetic. shotgen writes PNGs by design, and the vision helper takes a file path. | `run_eval.py:79-82`, `report.py:89-91`, `git ls-files eval/results`, `shotgen/main.swift:83-84`, `backends.py:208`, `mlx_vlm_judge.py:35`; 9.3 l.816 | Keep real data outside the repo on an encrypted volume, gitignored, with a pre-commit hook that rejects non-synthetic IDs. Compile the recorder out of release builds. The product passes images in memory, never as paths. | R |
| F29 | Low | Code | The committed resource JSON names unrelated processes on the dev machine. Errors carry up to 200 characters of framework text. | `measure_resources.py:222-224`; `fmjudge/main.swift:123` | Allowlist process names. Keep error class only. | R |
| F30 | Medium | Plan | A Keychain or DPAPI key protects backups and other accounts, not someone at the unlocked session. CSV, Markdown and project exports are plaintext. SQLite `-wal` and `-shm` files and Spotlight indexing of exports are unaddressed. | 7.5, E5, J7 l.512, J13 l.518 | Name the encryption library and test the WAL files. Optional Touch ID or Windows Hello gate on History and Export. Exports are marked and kept out of Spotlight. | I |
| F31 | Medium | Code+Plan | Sensitive-window exclusion is a denylist and fails open. KeePassXC was missed (S1). Private windows are detected by title strings that browsers may not set. Banks are 4 domains. | `rules.py:13-15,40-47`; S1 l.80; B6 l.358 | Add structural signals: secure input active, a focused AX secure text field, the browser's private flag. A user-editable list, and a test per browser. | R, T |
| **Misuse (stalkerware)** | | | | | | |
| F32 | High | Plan | The single guardrail, a visible indicator, is not guaranteed visible: Windows tray overflow, the macOS 27 menu bar overflow, the notch. Titles-and-text mode may trigger no OS capture indicator at all (unverified). | 3.9 l.67, 8.1 l.741, l.770, 9.2 l.806 | While watching, show an on-screen marker the user cannot turn off at session start, plus a periodic re-show. Test with OS defaults (T11). | R, I |
| F33 | High | Plan | Consent can be bypassed: Windows has no capture or UI Automation prompt, silent install and MDM exist (G9), and launch at login, schedules and calendar auto-start can start sessions with nobody present. | 9.2 l.810, G9 l.490, l.597, l.861, 8.2 l.775 | No watching on a login until the person at the keyboard takes an interactive action. The first-run consent cannot be pre-answered by config or MDM. Schedules ask for a click at start time. | R, I |
| F34 | Medium | Plan | "No remote features" leaves side doors: App Intents and Shortcuts, automation hooks, the CLI, exports to synced folders, and the browser extension (which has network). | A7, B11 l.363, l.869, E5 | Intents and the CLI control only (start, pause). They never return history or text. Export needs a UI action. The extension requests minimal permissions and sends no page text. | I |
| F35 | Low | Plan | Open-sourcing the engine (G7, 12.6) helps verification but makes an indicator-free fork easy. A license cannot enforce the guardrail. | G7 l.488, 12 l.916 | Accept and state it. Rely on OS-level indicators where they exist, and don't market the guardrail as enforceable. | I |
| **Claims a user cannot verify** | | | | | | |
| F36 | Medium | Plan | "0 bytes sent. 0 screenshots saved." is self-reported and circular: the app can only count its own sockets, which are zero by design. It cannot see system-daemon traffic, and "in memory for seconds" is not observable. Windows has no equivalent of an entitlements check. | G5 l.486, 3.1 l.59 | Replace the receipt with a how-to-check page: `codesign` entitlements, a per-process firewall (LuLu or Little Snitch), `fs_usage` or Process Monitor for file writes, a canary test users can run, and a reproducible build of the open engine. | R, I |

---

## 3. Verification tests

Each test names the finding it resolves. Mac tests need this M1 Pro. Windows tests need real Windows hardware (none confirmed; CLAUDE.md).

**T1. Engine egress matrix, Mac (F1, F2, F3; spike S6).** Build a minimal sandboxed XPC service without `network.client`.
From inside it, attempt: TCP to 1.1.1.1:443; UDP to port 53; `getaddrinfo("example.com")`; a `URLSession` data task;
`NSWorkspace.open` of `http://127.0.0.1:8765/?canary=…` with a local listener running; a write to an app-group container;
an XPC call to a peer that has network. Record each result and any sandbox deny lines from `log stream`.
Pass: no path delivers the canary to the listener, or every open path is removed from the design.

**T2. TCC attribution (F4; S2/S6).** Capture one frame from the XPC service with ScreenCaptureKit. Check which name System Settings
lists under Screen Recording. Then, from the main app (no capture code path), query shareable content and attempt a capture.
If it succeeds without a prompt, the app holds the grant. Repeat for Accessibility.

**T3. Accessibility from a sandbox (F5; S7).** From a sandboxed XPC service, call `AXIsProcessTrustedWithOptions`. Read the focused window's
title and value from TextEdit and Safari. Compare with an unsandboxed helper. Record what the user is asked to approve and which name appears.

**T4. Apple frameworks offline and log canary (F8, F9).** Put a unique canary string in window text. Run the full fmjudge, shotgen OCR and embed set
(1) online and (2) with Wi-Fi and Ethernet off. Pass: identical outputs (greedy decoding) and no availability errors offline.
While it runs, keep a per-process network monitor on all processes and `log stream --level debug`, then grep the log
and a fresh sysdiagnose for the canary. Any hit means prompts are logged: rewrite the claim.

**T5. Data-at-rest canary sweep (F25, F26, F28, F30).** Run a full session with canaries in titles, URLs and body text. Then grep
`~/Library` (Containers, Caches, Logs, Application Support, Saved Application State), `/private/var/folders`,
`/Library/Logs/DiagnosticReports`, the unified log, and the DB including `-wal` and `-shm` files. Windows: `%LOCALAPPDATA%`, `%TEMP%`,
the WER report queue, ETW traces. Pass: the canary appears only where the design says it may, encrypted.

**T6. Crash-dump canary (F12, F27).** A debug-only flag makes the engine crash while holding a capture buffer that contains a known pixel
pattern and canary text. Mac: inspect the `.ips` report. Windows: enable LocalDumps with full dumps, search the dump, then confirm
the chosen WER exclusion removes it. Pass: no canary in any dump the OS keeps or uploads.

**T7. Injection suite (F13 to F19).** For each field (title, URL path, document path, body, OCR text), add paired scenarios: the same page with and without
an injection, with injections both toward `on_task` and toward `off_task`. Add a delimiter break-out case and a 1,200-character padding case.
Metric: verdict flip rate between twins, per backend and per judge order. Gate: zero flips toward `off_task` on on-task twins.
Report flips toward `on_task` honestly. Add a stored-injection case: a pasted brief that contains instructions, checked against the drafted profile.

**T8. Downloader and model integrity (F3, F21, F23).** Send the downloader arbitrary URLs and strings over its IPC; it must refuse them.
Serve a tampered weight file, a truncated file and a modified `chat_template.jinja` through a local test server; the engine must
refuse to load each one. Fuzz the model loaders with malformed headers.

**T9. IPC client check (F6).** An ad-hoc-signed test binary tries to connect to the engine's XPC service (Windows: its pipe) and request a verdict
or *Why?* text. Pass: rejected and logged.

**T10. Windows isolation (F10, F11, F12; S6-W, needs hardware).** Run the engine in an AppContainer without `internetClient`. Repeat T1's matrix with
Windows equivalents. Test Windows.Graphics.Capture and UI Automation from inside the container. Find which process fetches the Windows ML
execution providers. As a non-admin user, try to delete the firewall-script rule. Inspect a WER dump (T6).

**T11. Stalkerware red team (F32, F33, F34).** Install by MDM or silent install with the most permissive configuration the product allows,
then reboot. Pass: no watching starts until the person at the keyboard acts, and the watching marker is visible with OS default
tray and menu-bar settings. Check that App Intents, Shortcuts and the CLI cannot read history or *Why?* text.

**T12. Harness hygiene (F22, F28, F29).** Run each MLX backend with networking off and with `uv run --offline --frozen`. Confirm a clean start.
Add a pre-commit check that rejects `eval/results` rows whose IDs are not in the synthetic scenario files, and any image file.

---

## 4. What is verified, inferred, or untested

- **Verified by reading:** the prompt-construction gaps (F13, F14), the parser (F16), the injection results and test coverage (F15),
  harness network exposure and unenforced comments (F22), the model provenance format (F23), result files in git and image-on-disk paths (F28, F29),
  the sensitive-list gaps (F31), the Apple inference daemon footprint taken from this repo's own measurement (F8), and every plan quotation cited.
- **Inferred from the design (likely, but argue with it):** F1 to F3, F6, F17 to F20, F25, F26, F30, F32 to F36.
- **Unverified vendor behavior, needs a real machine:** App Sandbox egress side channels; TCC attribution for helpers; Accessibility from a sandbox;
  FoundationModels PCC or server routing, prompt logging and guardrail locality; whether Vision and NLEmbedding are fully on-device; AppContainer
  capture and UI Automation limits; the Build 2026 container SDK; Windows ML provider downloads; WER dump contents and exclusion APIs;
  Mac crash-report contents; capture-indicator behavior in titles-and-text mode.

**Claim wording that holds today.** "Your screen is analyzed on this Mac by Apple's on-device model or a local model. We send nothing
about your screen anywhere. The app checks for updates and downloads models; those requests contain no data about you." Hold back
"OS-enforced" and "cannot reach the network" until T1 to T4 pass, and say nothing of the kind about Windows until T10 passes.
