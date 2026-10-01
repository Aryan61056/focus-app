# Eval run: fm_swift:reason-first | text=full | rules=on

scenarios: 30 | text mode: full | rules: on | stages: {'model': 28, 'rule': 2}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 52.6% (10 of 19) | [32-73%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 84.2% | [62-94%] | >= 97% | no |
| Recall, clear distractions | 100.0% (of 7) | [65-100%] | >= 85% | yes |
| Recall, all off-task | 100.0% (of 10) | [72-100%] | n/a | |
| Accuracy, 3-way | 46.7% | | n/a | |
| False nudges on gold on_task | 23.1% | | | |
| Calibration error (stated confidence, n=28) | 0.337 | | < 0.05 | no |
| Model latency p50 / p95 | 2339 / 2801 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 3 | 7 | 3 |
| unsure | 0 | 1 | 6 |
| off_task | 0 | 0 | 10 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 19 | 52.6% | 84.2% | 100.0% |
| 50 | 19 | 52.6% | 84.2% | 100.0% |
| 70 | 19 | 52.6% | 84.2% | 100.0% |
| 80 | 18 | 55.6% | 88.9% | 100.0% |
| 90 | 18 | 55.6% | 88.9% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 3 | 33.3% | 2 | 1 | 0 |
| ai_assistants | 2 | 50.0% | 1 | 0 | 0 |
| messaging | 3 | 33.3% | 2 | 1 | 0 |
| neutral_nav | 3 | 33.3% | 1 | 1 | 0 |
| project_rules | 3 | 66.7% | 2 | 1 | 0 |
| social | 3 | 66.7% | 2 | 1 | 0 |
| web | 4 | 50.0% | 3 | 1 | 0 |
| work_apps | 5 | 60.0% | 3 | 1 | 0 |
| youtube | 4 | 25.0% | 3 | 2 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 19 | 52.6% | 9 | 2 | 0 |
| gray | 11 | 36.4% | 10 | 7 | 0 |

## Refusals and errors: 2 (counted as unsure)
- h-ai-01: error: May contain sensitive content
- h-yt-01: error: May contain sensitive content

## False nudges (predicted off_task, gold is not)

- h-adv-03 [gold unsure, conf 95] KeePassXC - Passwords -- Contains passwords, not physics experiment data.
- h-msg-03 [gold unsure, conf 95] Jordan -- Conversations about dinner are unrelated to investment pitch.
- h-nav-03 [gold unsure, conf 95] Classical Focus - Apple Music -- Playing classical music is unrelated to historical analysis.
- h-lnk-03 [gold on_task, conf 90] Pricing - Grid Insight -- Shows competitor pricing unrelated to pitch deck content.
- h-soc-02 [gold unsure, conf 95] r/androiddev - Reddit -- Not related to Android app settings or dark mode.
- h-web-03 [gold unsure, conf 90] Series A funding hits record in Q2 - TechCrunch -- Article provides market data irrelevant to pitch deck content.
- h-app-05 [gold on_task, conf 95] python analyze_pendulum.py - lab-report - zsh -- Output is code output, not report content.
- h-yt-03 [gold on_task, conf 70] Material 3 Dark Theme in Jetpack Compose - Android Developers - YouTube -- Discusses dark theme, not Android settings implementation.
- h-yt-04 [gold unsure, conf 90] How I Built a $10M Startup - Podcast Clip - YouTube -- Video contains startup advice irrelevant to pitch deck building.

## Missed off-task (gold off_task, predicted otherwise)

none
