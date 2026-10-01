# Eval run: mlx_text:Qwen3-4B-Instruct-2507-4bit:relation | text=full | rules=on

scenarios: 70 | text mode: full | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 78.3% (18 of 23) | [58-90%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 100.0% | [86-100%] | >= 97% | yes |
| Recall, clear distractions | 100.0% (of 15) | [80-100%] | >= 85% | yes |
| Recall, all off-task | 90.0% (of 20) | [70-97%] | n/a | |
| Accuracy, 3-way | 77.1% | | n/a | |
| False nudges on gold on_task | 0.0% | | | |
| Calibration error (stated confidence, n=4) | 0.000 | | < 0.05 | yes |
| Model latency p50 / p95 | 2561 / 3081 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 32 | 0 | 0 |
| unsure | 9 | 4 | 5 |
| off_task | 2 | 0 | 18 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 23 | 78.3% | 100.0% | 100.0% |
| 50 | 23 | 78.3% | 100.0% | 100.0% |
| 70 | 23 | 78.3% | 100.0% | 100.0% |
| 80 | 23 | 78.3% | 100.0% | 100.0% |
| 90 | 23 | 78.3% | 100.0% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 100.0% | 2 | 0 | 0 |
| ai_assistants | 6 | 83.3% | 2 | 0 | 0 |
| messaging | 8 | 75.0% | 2 | 1 | 0 |
| neutral_nav | 7 | 57.1% | 2 | 1 | 0 |
| project_rules | 6 | 83.3% | 1 | 0 | 0 |
| social | 7 | 71.4% | 3 | 1 | 0 |
| web | 10 | 80.0% | 7 | 1 | 0 |
| work_apps | 11 | 72.7% | 1 | 0 | 2 |
| youtube | 8 | 75.0% | 3 | 1 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 100.0% | 15 | 0 | 0 |
| gray | 29 | 44.8% | 8 | 5 | 2 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

- msg-06 [gold unsure, conf n/a] Mom -- Concerns personal meetup, not budgeting
- nav-06 [gold unsure, conf n/a] Deep Focus - Spotify -- Music playback, not blog content
- soc-04 [gold unsure, conf n/a] r/programming - Reddit -- Discusses programming, not bug fixing in checkout flow
- web-05 [gold unsure, conf n/a] Amazon.com: 7-in-1 USB-C Hub Adapter -- Sells hardware, not app onboarding
- yt-06 [gold unsure, conf n/a] lofi hip hop radio - beats to relax/study to - YouTube -- Music, not integration by parts problems

## Missed off-task (gold off_task, predicted otherwise)

- ide-05 [pred on_task, conf n/a] Board.swift - DungeonDash -- Code is unrelated to payments bug
- ide-10 [pred on_task, conf n/a] Wedding invitation (personal) - Figma -- Figma file for personal invitation design
