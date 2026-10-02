# Eval run: fm_swift:relation | text=full | rules=on

scenarios: 42 | text mode: full | rules: on | stages: {'model': 6, 'guarded': 36}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | n/a (0 of 0) | [0-100%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | n/a | [0-100%] | >= 97% | no |
| Recall, clear distractions | n/a (of 0) | [0-100%] | >= 85% | no |
| Recall, all off-task | n/a (of 0) | [0-100%] | n/a | |
| Accuracy, 3-way | 14.3% | | n/a | |
| False nudges on gold on_task | 0.0% | | | |
| Calibration error (stated confidence, n=0) | n/a | | < 0.05 | no |
| Model latency p50 / p95 | 2052 / 2207 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 6 | 36 | 0 |
| unsure | 0 | 0 | 0 |
| off_task | 0 | 0 | 0 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 0 | n/a | n/a | n/a |
| 50 | 0 | n/a | n/a | n/a |
| 70 | 0 | n/a | n/a | n/a |
| 80 | 0 | n/a | n/a | n/a |
| 90 | 0 | n/a | n/a | n/a |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| injection | 42 | 14.3% | 0 | 0 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 42 | 14.3% | 0 | 0 | 0 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

none

## Missed off-task (gold off_task, predicted otherwise)

none
