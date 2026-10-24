# Beta testing

How Hushd gets from this Mac to testers and how their feedback gets back, without breaking the on-device rule.
Tester-facing pages: the [README](../README.md) (the repository's front page), [beta/TESTER-GUIDE.md](beta/TESTER-GUIDE.md) and
[beta/TEST-PLAN.md](beta/TEST-PLAN.md).

## The loop

```
owner                                     tester                                       owner
tools/beta/release.sh   ── builds ──▶     README ▸ Download the beta                   tools/beta/feedback.py pull
  bumps beta/BUILD                        installs the DMG, Open Anyway once             files reports attached to `beta` issues
  stamps channel, end date, notes,        Beta page: ready checks, seven tries           (or: ingest <files> sent another way)
  known issues, GitHub project            works for a week; Today asks once a week     feedback.py report → beta/inbox/report.html
tools/beta/publish.sh <name>  ──▶         profile ▸ Send feedback ▸ preview ▸ save     feedback.py triage <id> fixed --issue "#12"
  GitHub pre-release: DMG + checksum      Post on GitHub: the form opens, drag file in  next release.sh, notes from what was fixed
                                  ◀── issue with the report file (or a file by hand) ──
```

Every hop between people is done by a person. Hushd never sends anything: it opens the GitHub form in the tester's browser when they
click, and the tester drags the saved file in and submits. The scripts never upload anything except `publish.sh`, which publishes the
build the owner made, and `feedback.py pull`, which only downloads report files attached to issues.

## On GitHub

| Piece | Where | What it does |
|---|---|---|
| Front page | `README.md` | Download link, what a tester needs, five install steps, how to send feedback, what a report holds and never holds. |
| Releases | <https://github.com/Aryan61056/focus-app/releases> | One pre-release per beta, tag `v<version>-beta.<n>` at the commit it was built from, with the DMG and its SHA-256 file attached and the text from `github-release.md` (install steps, new in this build, known issues, links to the forms). |
| Issue forms | `.github/ISSUE_TEMPLATE/beta-bug.yml`, `beta-wrong-call.yml`, `beta-idea.yml` | Labelled `beta` plus `bug`, `wrong call` or `idea`. Each has a Build field Hushd fills through the address (`?template=…&title=…&build=…`, nothing else), the tester's own words, and a box to drop the report file in. The wrong-call form asks for the *kind* of window, never its contents. `config.yml` links the tester guide and the downloads. |
| Labels | the repository | `beta`, `wrong call`, `idea` (and GitHub's own `bug`). `feedback.py pull` reads issues labelled `beta`. |

## In the app

| Piece | Where | What it does |
|---|---|---|
| Profile | Bottom left of the sidebar | Avatar, name (shared with Friends), build tag, a dot when the beta has something for you. Popover: edit name and avatar, the build with a ring of days left and a bar of the seven tries, Send feedback, Report a wrong call, What's new, Get the newest build (opens the releases page), Beta page. **A local profile, not an account** (see below). |
| Beta page | Settings ▸ Beta, the profile, Help ▸ Beta Page | Days left as a ring and the build; **Ready to test**: three checks (Apple's model, window titles, the beta log) with a Fix button for any that needs the tester; the seven tries as a bar and a two-column list; Send feedback and Wrong call, and where reports go; the log switches. |
| Feedback sheet | Profile, Help ▸ Send Feedback (⌥⌘F), the Beta page, Today notices | Kind as four pills, the tester's words, five checkboxes for what goes with it, "See the whole file" shows the exact JSON. With a GitHub project: **Post on GitHub** saves the file, then shows it as a tile to drag and three steps with **Open the form**; **Save file** is beside it. With an address: **Email report** opens a mail draft with the file attached. With neither: **Save report**. "Issues are public" sits beside the buttons. |
| Welcome | Today, first launch of any beta build | "Thanks for testing beta N. The Beta page has seven things to try." Open Beta or Later; never again after either. |
| Beta log | `~/Library/Application Support/Hushd/beta.json` (0600) | Up to 600 events: launch, quit, unclean exit, session start and end (minutes), warning, pause screen, check-in, Back to task (found or not), model refusal or unavailable, slow moment (seconds), report saved, weekly answer. Kinds, times and numbers only. Switch and Clear on the Beta page. |
| Unclean exits | `running.marker` beside the log | Written at launch, removed on a clean quit. Still there at the next launch means a crash, force quit or power loss: logged, and Today offers "Write a report" once. |
| Slow moments | `HangWatch` | A main-thread timer that notices when it fired two seconds or more late while Hushd is in front. Gaps over a minute are sleep, not hangs. No sampling, no second thread. |
| Crash summary | Read from macOS's own `~/Library/Logs/DiagnosticReports/focus-app-*.ips` | Exception, signal, termination and up to 24 frames of the crashed thread as `image symbol`. Paths, incident and device IDs and the app-specific text block are dropped. Only goes in a report when the tester leaves "The last crash" ticked. |
| Recent calls | `SessionController.readings` (memory, the current or last session) | Up to 12 of Hushd's calls as `on`/`unsure`/`off` and how: `model`, `rule`, `words`, `refused`, `private`, `skipped`. Never the app, title, address, key or reason. Checkbox "Hushd's last calls", shown only when there are calls. |
| Weekly question | Today, between sessions | "How is Hushd working for you this week?" Five dots, one click, Skip. Only after three finished sessions, at most once a week, never during a session. Switch on the Beta page. |
| Missions | Beta page, profile bar | Seven things to try (finish a session, 25 minutes, describe a project, Back to task, answer Review, three days, send a report). Each ticks itself from what is already on the Mac; none needs typing. |
| What's new | Today notice once per build, profile, Help | The build's release notes and, under "Known, no report needed", its known issues. |
| End date | Today notice, profile, Beta page | After it: "This beta build is out of date. A newer one is on GitHub." with **Get the newest**. The app keeps working; a beta never locks anyone out of their own data, and Hushd never downloads or installs anything itself. |

### What a report holds

Schema `focus-feedback/1` ([fixture](../tools/beta/fixtures/sample-report.json)). Always: the tester's words, kind, optional contact they typed (the field is hidden when reports go to GitHub, where the issue already says who posted it), app version, build, build ID, channel.
Each optional and on by default: macOS version, Mac model, memory, Apple silicon, Low Power, model ready or not, permission states, switches and choices from Settings (the never-judged list as a count only); counts from the last 14 days (sessions, minutes, drifts, nudges, refusals, read totals, Review answers, projects and how many are described, days used); the last 14 days of the beta log and weekly answers; Hushd's recent calls; the crash summary.

**Never:** task or project names, project descriptions, window titles, addresses, words read from the screen, pictures, model reasons, parked thoughts, the notch line, the profile name. `BetaTests.testReportCarriesNoTaskProjectTitleOrScreenText` plants each of those in a store and fails if any reaches the file; `testRecentCallsSayHowNeverWhichWindow` does the same for the calls.

**Public.** A report posted on GitHub is public. The tester sees the whole file first, the sheet says "Issues are public", and the forms say it again.

### Why a profile and not accounts

The owner asked for "accounts … on the bottom left" (2026-10-18). Sign-in accounts need a server and would reverse a standing decision ("no accounts, no telemetry", CLAUDE.md, PRODUCT.md principle 6), so this build puts a **local profile** there: the same name and avatar Friends uses, stored on this Mac. A tester's GitHub account is theirs and only touches GitHub, in their browser. If the owner does want real accounts, the options are Sign in with Apple through the existing CloudKit container (no server of ours) or a hosted service; both are the owner's call and neither is built.

## Owner tools

```bash
tools/beta/release.sh --dry-run                                   # what the next beta would be
tools/beta/release.sh [--days 30] [--email beta@your.domain]      # build it: beta/releases/<version>-beta.<n>/
tools/beta/publish.sh 0.1.0-beta.2 --dry-run                      # check it and show the GitHub release text
tools/beta/publish.sh 0.1.0-beta.2                                # publish it as a GitHub pre-release (asks; --yes skips the question)
tools/beta/feedback.py pull                                       # reports attached to `beta` issues → beta/inbox/
tools/beta/feedback.py ingest ~/Downloads/focus-feedback-*.json   # reports that came another way
tools/beta/feedback.py list --status new
tools/beta/feedback.py triage 6f1c fixed --issue "#12" --note "guarded tick"
tools/beta/feedback.py report                                     # beta/inbox/REPORT.md and report.html
tools/beta/testers.py add Sam --mac "M1 Pro, macOS 27"            # roster in beta/testers.csv (gitignored), for builds handed out by hand
python3 -m unittest discover -s tools/beta -p 'test_*.py'
```

- `release.sh` reads notes from `beta/notes/next.md` and known issues from `beta/notes/known.md`, takes the GitHub project from the
  `origin` remote (`--repo URL` to choose another, `--no-repo` for a build with no GitHub links), bumps `beta/BUILD` only after the image
  is built and checked, and refuses to overwrite a release folder. It warns when `mac/`, `core/` or `tools/` have uncommitted changes.
  The folder gets the image, checksum, `release.json`, `notes.md`, `known.md`, `invite.txt` (for handing it out by hand) and
  `github-release.md`. Signing follows `tools/build_app.sh` (ad-hoc unless a Developer ID is set); the texts say "Open Anyway" for an
  ad-hoc build. The words come from `tools/beta/release_text.py`, which is tested.
- `publish.sh` checks the image against its recorded checksum, that `gh` is signed in, that the build's commit is already on `origin`
  (so the tag points at code testers can read) and that the tag is not published yet, then runs `gh release create --prerelease` and
  records the date in `release.json`. Undo: `gh release delete v<name> --cleanup-tag`.
- `feedback.py pull` lists the issues labelled `beta` with `gh`, finds `.json` files attached to them or their comments
  (`github.com/user-attachments/files/…` and the older `github.com/<owner>/<repo>/files/…`; nothing else), downloads each once into a
  fresh temporary folder (512 KB at most), then files it exactly like `ingest`, with the issue number recorded. A file the app could
  not have written is refused and listed, as with `ingest`.
- `feedback.py ingest` **refuses** files the app could not have written: wrong schema, unknown keys or event kinds, an unknown call or
  source, a file path anywhere, long text outside the tester's message, more than 512 KB. It **warns** (and still files) when the tester's
  own words look like a password, card number or API key, so you can delete them. Duplicates (same report ID) are filed once.
- `feedback.py report` de-duplicates journal events across reports from the same tester, groups crashes by exception plus the first Hushd
  frame, and for wrong calls counts how Hushd reached its newest call (model, rule, words). The HTML page is static, has no scripts or
  outside addresses, follows light and dark, and is never published.

Gitignored: `beta/inbox/`, `beta/releases/`, `beta/testers.csv`. Committed: `beta/BUILD`, `beta/notes/`.

## Build keys

`tools/build_app.sh` stamps these when set (`release.sh` sets all but the email for you):
`FOCUS_CHANNEL` (dev, beta, release) → `FocusChannel`; `FOCUS_BUILD_NUMBER` → `CFBundleVersion`; `FOCUS_VERSION` → `CFBundleShortVersionString`;
`FOCUS_BETA_EXPIRES` (YYYY-MM-DD) → `FocusBetaExpires`; `FOCUS_FEEDBACK_EMAIL` → `FocusFeedbackAddress`;
`FOCUS_FEEDBACK_REPO` (`https://github.com/<owner>/<repo>`, checked) → `FocusFeedbackRepo`; `FOCUS_RELEASE_NOTES_FILE` → `FocusReleaseNotes`;
`FOCUS_KNOWN_ISSUES_FILE` → `FocusKnownIssues`.
The app accepts a project address only if it is `https://github.com/<owner>/<repo>` exactly, and the app side (`focus-app/Beta.swift`,
outside the scanned engine modules) opens nothing but `https://github.com` pages, and only on a click.
No `FocusChannel` means a dev build: the profile says "Dev build" and the beta pieces still work, so the owner tests them too. A `release`
build keeps Help ▸ Send Feedback and drops the weekly question and crash notice.

## Decisions still the owner's

- Who tests and how many. Builds now reach testers through public GitHub pre-releases (owner, 2026-10-19: "improve the github so it
  allows users to start beta testing"); handing the DMG out by hand still works. No TestFlight (owner, 2026-10-18).
- The feedback address, if any (`--email`).
- Developer ID signing and notarization (removes "Open Anyway" and turns Friends and iPhone sync on); the bundle ID is still the placeholder.
- Whether real accounts are wanted (above).
- The beta's length (`--days`, default 30) and whether the weekly question stays on by default.

## Verified and not

See the last section of [STATUS.md](STATUS.md) for what was run on 2026-10-19 and what was not.
