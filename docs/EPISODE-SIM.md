# Episode simulator: false nudges per session

Tool: `mac/Sources/BrainSim` and the `brain-sim` command. Written 2026-10-01. Everything here is simulated on synthetic scenarios; nothing was measured on a person.

## What it does

Per-moment accuracy (S1) cannot say how often a person gets a wrong nudge, because the brain waits for time, repetition and two independent verdicts. The simulator replays real recorded verdicts through the real brain:

- Verdicts: Apple's on-device model with the two-judge rule and the refusal fix, for all 100 scenarios (`eval/results/verdicts_two_judge.json`, made by `eval/export_verdicts.py`). The model is greedy, so a given window always gets the same verdict, as in the app.
- The brain: the same Swift code that passes the golden traces. The simulator plays the senses: it answers each `RequestJudgment` after 3.5 s, sends window changes, and reacts to nudges.
- User behavior: an assumption, stated below. This is the weak part.

```bash
cd mac && swift build -c release
.build/release/brain-sim --verdicts ../eval/results/verdicts_two_judge.json --episodes 300 [--preset Gentle|Standard|Strict] [--shadow] [--neutral-defaults] [--p-off 0.12] [--p-unsure 0.17] [--p-return 0.7] [--churn 30]
```

## Behavior assumptions (defaults)

Session of 3 hours made of windows drawn at random from the scenario pool: 70% on-task, 17% unsure (messages, music, new tab), 12% off-task, 1% sensitive. Dwell times are log-uniform: on-task 20 to 400 s, unsure 10 to 180 s, off-task 15 to 600 s. Content inside a window changes every 30 s. After a nudge the user returns to work within 3 to 20 s with probability 0.7, otherwise carries on. A nudge arriving within 6 s of the user already leaving a distraction is counted as "late", not false.

## Results (300 episodes of 3 h per row, Standard preset unless stated)

| Run | Nudges per 3 h | False nudges per 3 h | Sessions with at least one false nudge | Distractions of 2 min or more nudged while still there |
|---|---|---|---|---|
| Baseline | 4.8 | 1.06 | 64% (95% CI 59 to 70) | 43% |
| Gentle | 3.2 | 0.63 | 48% | 33% |
| Strict | 5.1 | 1.25 | 71% | 44% |
| Shadow (would-be nudges) | 5.4 | 1.22 | 72% | 43% |
| Fewer gray moments (8% unsure) | 4.0 | 0.41 | 34% | 43% |
| More gray moments (30% unsure) | 6.3 | 2.08 | 88% | 43% |
| Fewer distractions (5% off) | 2.8 | 1.12 | 67% | 42% |
| More distractions (25% off) | 8.8 | 0.96 | 61% | 44% |
| **Messaging and start pages never judged** | 3.8 | **0.00** | **0% (CI 0 to 1)** | 44% |

Other numbers: about 104 model judgments per hour in this heavy-drift mix (the brain spec estimated 32 for a focused hour and 84 for a drifting one; each judgment is up to two model calls). Median time from the start of a distraction to the first nudge is 32 s, because a gray window just before it has already started the block's timer; the 90th percentile is 75 s on Standard.

## What it shows

1. **With the Apple model alone, Standard nudges would be too noisy.** About one false nudge per 3 hours on average, and about two sessions in three get at least one. The PLAN's bar was "about one false nudge per 3 hours", so this is at the limit on average and well past it for the typical session. This supports the owner's safeguards: shadow mode first, and nothing nudges on `unsure`.
2. **Almost all false nudges come from three windows**: two personal-message windows ("Mom", "Jordan") and a new-tab page. The model calls them off task with both framings agreeing, and a person can sit on them for minutes, so the time and pair rules do not help (the brain spec's riskiest decision 1, now measured).
3. **A default allow-list for personal messaging and start pages removes those false nudges in this pool and costs nothing measurable in catching real distractions** (44% vs 43%). This is the brain spec's open question 3. It is the owner's call because it decides what the app ignores by default.
4. **Gentle halves the false rate but also catches fewer distractions** (33% nudged while present). Preset choice trades one for the other.
5. **Catch rate is limited by the model, not the brain**: about 44% of distractions of 2 minutes or more get a nudge while the person is still there, because the model calls many gray distractions `unsure`, and `unsure` never nudges by design.

## What not to conclude

- The 0.00 with messaging allowed is not a result about the world. I picked that rule after seeing which three windows failed, in a pool of 100 windows I wrote. Other windows will fail in ways this pool does not contain. Treat it as "these three are the whole problem here", and as a regression guard, not as a guarantee. The fix is more scenarios (fresh, not tuned on), not trust in this number.
- The mix, dwell times and return behavior are guesses. The table shows the result moves a lot with the share of gray moments (0.4 to 2.1 false nudges per 3 h), so real usage data would matter more than any tuning here.
- Gold labels are one labeler's. No second labeler yet.
- "Late" nudges are about 0.04 per 3 h and counted separately; to the user they would still feel like a nudge after they had already come back.

## Needs your decision

Should personal messaging apps, music players and new-tab or start pages be on a default "never judged" list that the user can change per project? Recommended yes (principle 1: a false nudge costs more than a miss, and in this simulation it costs almost nothing in catches). Until you decide, the code ships no such list; the simulator flag only measures the effect.
