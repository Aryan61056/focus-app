# Eval run: oracle | text=ocr | rules=on

scenarios: 70 | text mode: ocr | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 100.0% (20 of 20) | [84-100%] | >= 97% | yes |
| Off-task precision, lenient (only gold on_task counts) | 100.0% | [84-100%] | >= 97% | yes |
| Recall, clear distractions | 100.0% (of 15) | [80-100%] | >= 85% | yes |
| Recall, all off-task | 100.0% (of 20) | [84-100%] | n/a | |
| Accuracy, 3-way | 100.0% | | n/a | |
| False nudges on gold on_task | 0.0% | | | |
| Calibration error (stated confidence, n=67) | 0.000 | | < 0.05 | yes |
| Model latency p50 / p95 | 0 / 0 ms | | text judge < 2000 ms | yes |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 32 | 0 | 0 |
| unsure | 0 | 18 | 0 |
| off_task | 0 | 0 | 20 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 20 | 100.0% | 100.0% | 100.0% |
| 50 | 20 | 100.0% | 100.0% | 100.0% |
| 70 | 20 | 100.0% | 100.0% | 100.0% |
| 80 | 20 | 100.0% | 100.0% | 100.0% |
| 90 | 20 | 100.0% | 100.0% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 100.0% | 2 | 0 | 0 |
| ai_assistants | 6 | 100.0% | 2 | 0 | 0 |
| messaging | 8 | 100.0% | 1 | 0 | 0 |
| neutral_nav | 7 | 100.0% | 1 | 0 | 0 |
| project_rules | 6 | 100.0% | 1 | 0 | 0 |
| social | 7 | 100.0% | 2 | 0 | 0 |
| web | 10 | 100.0% | 6 | 0 | 0 |
| work_apps | 11 | 100.0% | 3 | 0 | 0 |
| youtube | 8 | 100.0% | 2 | 0 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 100.0% | 15 | 0 | 0 |
| gray | 29 | 100.0% | 5 | 0 | 0 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

none

## Missed off-task (gold off_task, predicted otherwise)

none
