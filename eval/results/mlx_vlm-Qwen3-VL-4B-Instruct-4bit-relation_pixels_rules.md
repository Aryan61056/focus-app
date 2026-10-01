# Eval run: mlx_vlm:Qwen3-VL-4B-Instruct-4bit:relation | text=pixels | rules=on

scenarios: 70 | text mode: pixels | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 74.1% (20 of 27) | [55-87%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 100.0% | [88-100%] | >= 97% | yes |
| Recall, clear distractions | 100.0% (of 15) | [80-100%] | >= 85% | yes |
| Recall, all off-task | 100.0% (of 20) | [84-100%] | n/a | |
| Accuracy, 3-way | 80.0% | | n/a | |
| False nudges on gold on_task | 0.0% | | | |
| Calibration error (stated confidence, n=4) | 0.000 | | < 0.05 | yes |
| Model latency p50 / p95 | 7006 / 7331 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 32 | 0 | 0 |
| unsure | 7 | 4 | 7 |
| off_task | 0 | 0 | 20 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 27 | 74.1% | 100.0% | 100.0% |
| 50 | 27 | 74.1% | 100.0% | 100.0% |
| 70 | 27 | 74.1% | 100.0% | 100.0% |
| 80 | 27 | 74.1% | 100.0% | 100.0% |
| 90 | 27 | 74.1% | 100.0% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 100.0% | 2 | 0 | 0 |
| ai_assistants | 6 | 83.3% | 2 | 0 | 0 |
| messaging | 8 | 75.0% | 2 | 1 | 0 |
| neutral_nav | 7 | 71.4% | 2 | 1 | 0 |
| project_rules | 6 | 83.3% | 1 | 0 | 0 |
| social | 7 | 71.4% | 4 | 2 | 0 |
| web | 10 | 80.0% | 8 | 2 | 0 |
| work_apps | 11 | 81.8% | 3 | 0 | 0 |
| youtube | 8 | 75.0% | 3 | 1 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 100.0% | 15 | 0 | 0 |
| gray | 29 | 51.7% | 12 | 7 | 0 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

- msg-06 [gold unsure, conf n/a] Mom -- Personal message, not finance-related
- nav-06 [gold unsure, conf n/a] Deep Focus - Spotify -- Music player, not blog post related
- soc-04 [gold unsure, conf n/a] r/programming - Reddit -- Unrelated to payment bug fixing
- soc-06 [gold unsure, conf n/a] Home / X -- Not product launch content or tools
- web-05 [gold unsure, conf n/a] Amazon.com: 7-in-1 USB-C Hub Adapter -- Shopping for hardware, not Figma onboarding design
- web-06 [gold unsure, conf n/a] Fed signals September rate cut - The New York Times -- Budget prep unrelated to financial news
- yt-04 [gold unsure, conf n/a] YouTube -- Not related to calculus homework

## Missed off-task (gold off_task, predicted otherwise)

none
