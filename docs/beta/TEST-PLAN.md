# Beta test plan

What each beta round is for, what testers are asked to do, and what has to be true before the next step. The owner sets the
audience and the size; the numbers below are starting targets to tune, not decisions.

## Rounds

| Round | Who | Length | Goal |
|---|---|---|---|
| 0. Owner | The owner, on this Mac | 3 days | Install from the DMG like a tester. `docs/REAL-USE-TEST.md` passes. Every Today notice and the feedback sheet seen once. |
| 1. Friends | 3 to 5 people the owner knows, mixed Macs | 1 week | Install from the GitHub release works without help. No crash loops. Wrong-call reports describe windows well enough to act on. |
| 2. Closed | 10 to 20 people in the target audience (owner's choice) | 2 weeks | False nudges rare enough that people keep nudges on. Weekly answers hold or rise. |
| 3. Wider | Owner's choice | 2 to 4 weeks | Release candidate. Signed and notarized if the owner has chosen to. |

## Each tester, each round

The seven missions in Settings > Beta: finish a session, stay 25 minutes, describe a project, use Back to task, answer a Review moment, use Focus on three days, send one report. Plus the weekly question.

## What we read

From `tools/beta/feedback.py report`, per build:

| Measure | Where it comes from | Starting target to move on |
|---|---|---|
| Unclean exits per 100 launches | beta log | under 2 |
| Slow moments (2 s or more) per session | beta log | under 0.2 |
| Nudges per session | beta log | watch only: compare with the episode simulator (`docs/EPISODE-SIM.md`) |
| Back to task found the place | beta log | 90% or more |
| Review: Focus was right | usage counts | rising; small samples, so read the counts, not the percentage |
| Wrong-call reports | report kinds | each one triaged within a week |
| Wrong calls: how Focus decided | recent calls in wrong-call reports | watch only: a pile-up on `model` points at the prompt, on `words` at the matching-words rule, on `rule` at a list |
| Weekly answer | weekly question | mean 3.5 or more, and not falling between rounds |
| Crashes | crash summaries | no signature from more than one tester left open |

These are per-moment and per-tester counts from a handful of people. They are hints, not measurements, and none can certify the accuracy targets in PLAN.md section 9. Say so whenever quoting them.

## Triage

Weekly: `pull` (reports posted on GitHub) and `ingest` (files that came another way), `report`, then for each new report `triage <id> triaged|fixing|wontfix|duplicate`. Fix order follows `docs/REAL-USE-TEST.md`: privacy and false nudges first, then wrong or stale sensing, missed nudges, Back to task, visuals. A fix closes with `triage <id> fixed --issue <ref>` (pulled reports already carry their issue), and the next build's `beta/notes/next.md` says what changed in plain words. Anything a tester should not report again goes in `beta/notes/known.md` until it is fixed.

A report the tool refuses is never "fixed by editing": the app cannot write it, so ask the tester how it was made.

## Exit from beta

All of: two consecutive builds meet the targets above; no open privacy report; T1 to T4 in `docs/SECURITY-REVIEW.md` decided by the owner; signing and distribution decided by the owner.
