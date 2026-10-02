# Eval run: oracle | text=full | rules=on

scenarios: 47 | text mode: full | rules: on | stages: {'model': 43, 'rule': 2, 'sensitive': 2}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 100.0% (15 of 15) | [80-100%] | >= 97% | yes |
| Off-task precision, lenient (only gold on_task counts) | 100.0% | [80-100%] | >= 97% | yes |
| Recall, clear distractions | 100.0% (of 10) | [72-100%] | >= 85% | yes |
| Recall, all off-task | 100.0% (of 15) | [80-100%] | n/a | |
| Accuracy, 3-way | 100.0% | | n/a | |
| False nudges on gold on_task | 0.0% | | | |
| Calibration error (stated confidence, n=45) | 0.000 | | < 0.05 | yes |
| Model latency p50 / p95 | 0 / 0 ms | | text judge < 2000 ms | yes |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 17 | 0 | 0 |
| unsure | 0 | 15 | 0 |
| off_task | 0 | 0 | 15 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 15 | 100.0% | 100.0% | 100.0% |
| 50 | 15 | 100.0% | 100.0% | 100.0% |
| 70 | 15 | 100.0% | 100.0% | 100.0% |
| 80 | 15 | 100.0% | 100.0% | 100.0% |
| 90 | 15 | 100.0% | 100.0% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 4 | 100.0% | 1 | 0 | 0 |
| ai_assistants | 3 | 100.0% | 1 | 0 | 0 |
| messaging | 4 | 100.0% | 0 | 0 | 0 |
| neutral_nav | 4 | 100.0% | 0 | 0 | 0 |
| project_rules | 7 | 100.0% | 3 | 0 | 0 |
| social | 5 | 100.0% | 3 | 0 | 0 |
| web | 8 | 100.0% | 2 | 0 | 0 |
| work_apps | 7 | 100.0% | 3 | 0 | 0 |
| youtube | 5 | 100.0% | 2 | 0 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 19 | 100.0% | 10 | 0 | 0 |
| gray | 28 | 100.0% | 5 | 0 | 0 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

none

## Missed off-task (gold off_task, predicted otherwise)

none
