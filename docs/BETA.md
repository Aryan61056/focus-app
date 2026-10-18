# Beta testing

How Focus gets from this Mac to testers and how their feedback gets back, without breaking the on-device rule.
Tester-facing pages: [beta/TESTER-GUIDE.md](beta/TESTER-GUIDE.md) and [beta/TEST-PLAN.md](beta/TEST-PLAN.md).

## The loop

```
owner                                   tester                                   owner
tools/beta/release.sh  ──DMG + invite──▶  installs, works for a week               tools/beta/feedback.py ingest <files>
  bumps beta/BUILD                         missions tick themselves                  report → beta/inbox/report.html
  stamps channel, end date, notes          Today asks one weekly question            triage <id> fixed --issue …
  writes beta/releases/<name>/             profile ▸ Send feedback ▸ preview ▸ save  next release.sh, notes from what was fixed
                                 ◀──report file (mail, AirDrop, chat)──
```

Every hop between people is done by a person. Focus never sends anything, the scripts never upload anything.

## In the app

| Piece | Where | What it does |
|---|---|---|
| Profile | Bottom left of the sidebar | Avatar, name (shared with Friends), build tag, a dot when the beta has something for you. Popover: edit name and avatar, build and days left, a ring of missions done, Send feedback, Report a wrong call, What's new, Beta settings. **A local profile, not an account** (see below). |
| Feedback sheet | Profile, Help ▸ Send Feedback (⌥⌘F), Settings ▸ Beta, Today notices | Kind (Something broke, Wrong call, Idea, Other), the tester's words, optional contact, four checkboxes for what goes with it, "See the whole file" shows the exact JSON. Saves a `.json` file; if the build names an address, "Email report" opens a draft in the tester's mail app with the file attached. |
| Beta log | `~/Library/Application Support/Focus/beta.json` (0600) | Up to 600 events: launch, quit, unclean exit, session start and end (minutes), warning, pause screen, check-in, Back to task (found or not), model refusal or unavailable, slow moment (seconds), report saved, weekly answer. Kinds, times and numbers only. Switch and Clear in Settings ▸ Beta. |
| Unclean exits | `running.marker` beside the log | Written at launch, removed on a clean quit. Still there at the next launch means a crash, force quit or power loss: logged, and Today offers "Write a report" once. |
| Slow moments | `HangWatch` | A main-thread timer that notices when it fired two seconds or more late while Focus is in front. Gaps over a minute are sleep, not hangs. No sampling, no second thread. |
| Crash summary | Read from macOS's own `~/Library/Logs/DiagnosticReports/focus-app-*.ips` | Exception, signal, termination and up to 24 frames of the crashed thread as `image symbol`. Paths, incident and device IDs and the app-specific text block are dropped. Only goes in a report when the tester leaves "The last crash" ticked. |
| Weekly question | Today, between sessions | "How is Focus working for you this week?" Five dots, one click, Skip. Only after three finished sessions, at most once a week, never during a session. Switch in Settings ▸ Beta. |
| Missions | Settings ▸ Beta, profile ring | Seven things to try (finish a session, 25 minutes, describe a project, Back to task, answer Review, three days, send a report). Each ticks itself from what is already on the Mac; none needs typing. |
| What's new | Today notice once per build, profile, Help | The build's release notes. |
| End date | Today notice, profile | After it, "This beta build is out of date." The app keeps working; a beta never locks anyone out of their own data. |

### What a report holds

Schema `focus-feedback/1` ([fixture](../tools/beta/fixtures/sample-report.json)). Always: the tester's words, kind, optional contact they typed, app version, build, build ID, channel.
Each optional and on by default: macOS version, Mac model, memory, Apple silicon, Low Power, model ready or not, permission states, switches and choices from Settings (the never-judged list as a count only); counts from the last 14 days (sessions, minutes, drifts, nudges, refusals, read totals, Review answers, projects and how many are described, days used); the last 14 days of the beta log and weekly answers; the crash summary.

**Never:** task or project names, project descriptions, window titles, addresses, words read from the screen, pictures, model reasons, parked thoughts, the notch line, the profile name. `BetaTests.testReportCarriesNoTaskProjectTitleOrScreenText` plants each of those in a store and fails if any reaches the file.

### Why a profile and not accounts

The owner asked for "accounts … on the bottom left" (2026-10-18). Sign-in accounts need a server and would reverse a standing decision ("no accounts, no telemetry", CLAUDE.md, PRODUCT.md principle 6), so this build puts a **local profile** there: the same name and avatar Friends uses, stored on this Mac. If the owner does want real accounts, the options are Sign in with Apple through the existing CloudKit container (no server of ours) or a hosted service; both are the owner's call and neither is built.

## Owner tools

```bash
tools/beta/release.sh --dry-run                                   # what the next beta would be
tools/beta/release.sh --days 30 [--email beta@your.domain]        # build it: beta/releases/<version>-beta.<n>/
tools/beta/testers.py add Sam --mac "M1 Pro, macOS 27"            # roster in beta/testers.csv (gitignored)
tools/beta/testers.py invite                                      # paste into your own message
tools/beta/testers.py sent Sam 0.1.0-beta.1
tools/beta/feedback.py ingest ~/Downloads/focus-feedback-*.json   # files into beta/inbox/ (gitignored)
tools/beta/feedback.py list --status new
tools/beta/feedback.py triage 6f1c fixed --issue "#12" --note "guarded tick"
tools/beta/feedback.py report                                     # beta/inbox/REPORT.md and report.html
python3 -m unittest discover -s tools/beta -p 'test_*.py'
```

- `release.sh` reads notes from `beta/notes/next.md`, bumps `beta/BUILD` only after the image is built and checked, and refuses to overwrite a release folder. It warns when `mac/`, `core/` or `tools/` have uncommitted changes. Signing follows `tools/build_app.sh` (ad-hoc unless a Developer ID is set); the invite says "Open Anyway" for an ad-hoc build.
- `feedback.py ingest` **refuses** files the app could not have written: wrong schema, unknown keys or event kinds, a file path anywhere, long text outside the tester's message, more than 512 KB. It **warns** (and still files) when the tester's own words look like a password, card number or API key, so you can delete them. Duplicates (same report ID) are filed once.
- `feedback.py report` de-duplicates journal events across reports from the same tester and groups crashes by exception plus the first Focus frame. The HTML page is static, has no scripts or outside addresses, follows light and dark, and is never published.

Gitignored: `beta/inbox/`, `beta/releases/`, `beta/testers.csv`. Committed: `beta/BUILD`, `beta/notes/`.

## Build keys

`tools/build_app.sh` stamps these when set (`release.sh` sets all but the email for you):
`FOCUS_CHANNEL` (dev, beta, release) → `FocusChannel`; `FOCUS_BUILD_NUMBER` → `CFBundleVersion`; `FOCUS_VERSION` → `CFBundleShortVersionString`;
`FOCUS_BETA_EXPIRES` (YYYY-MM-DD) → `FocusBetaExpires`; `FOCUS_FEEDBACK_EMAIL` → `FocusFeedbackAddress`; `FOCUS_RELEASE_NOTES_FILE` → `FocusReleaseNotes`.
No `FocusChannel` means a dev build: the profile says "Dev build" and the beta pieces still work, so the owner tests them too. A `release` build keeps Help ▸ Send Feedback and drops the weekly question and crash notice.

## Decisions still the owner's

- Who tests, how many, and how builds reach them. No TestFlight (owner, 2026-10-18): the DMG goes directly, by AirDrop, a shared iCloud Drive folder or a message attachment, with `invite.txt` and the checksum beside it. Testers install a new beta over the old one; their data stays.
- The feedback address, if any (`--email`). Without one, testers save the file and send it however you agreed.
- Developer ID signing and notarization (removes "Open Anyway"); the bundle ID is still the placeholder.
- Whether real accounts are wanted (above).
- The beta's length (`--days`, default 30) and whether the weekly question stays on by default.

## Verified and not

Verified on this Mac, 2026-10-18: 17 Swift tests (`BetaTests`: build keys, unclean exit across launches, log limits and file mode, weekly rules, notes once per build, hang thresholds, crash parsing with planted personal data, report privacy with planted secrets, unchecked sections left out, shape matches the Python fixture, missions, controller hooks, saving), 18 Python tests (`tools/beta/test_beta_tools.py`: validation and refusals, warnings, ingest and dedupe, triage, summary numbers, HTML inert and escaped, roster), privacy scan 0 findings.

Not verified: a real crash report written by macOS for this app (the parser is tested on a synthetic `.ips` that follows Apple's format), `release.sh` producing a DMG end to end on a clean checkout, the mail hand-off with a real mail app, the hang watch under App Nap, the feedback sheet's save panel driven by hand, any tester on another Mac.
