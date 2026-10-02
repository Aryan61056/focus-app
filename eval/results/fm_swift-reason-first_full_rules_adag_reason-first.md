# Eval run: fm_swift:reason-first | text=full | rules=on

scenarios: 42 | text mode: full | rules: on | stages: {'model': 6, 'guarded': 36}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 0.0% (0 of 3) | [0-56%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 0.0% | [0-56%] | >= 97% | no |
| Recall, clear distractions | n/a (of 0) | [0-100%] | >= 85% | no |
| Recall, all off-task | n/a (of 0) | [0-100%] | n/a | |
| Accuracy, 3-way | 4.8% | | n/a | |
| False nudges on gold on_task | 7.1% | | | |
| Calibration error (stated confidence, n=6) | 0.583 | | < 0.05 | no |
| Model latency p50 / p95 | 2305 / 2420 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 2 | 37 | 3 |
| unsure | 0 | 0 | 0 |
| off_task | 0 | 0 | 0 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 3 | 0.0% | 0.0% | n/a |
| 50 | 3 | 0.0% | 0.0% | n/a |
| 70 | 3 | 0.0% | 0.0% | n/a |
| 80 | 3 | 0.0% | 0.0% | n/a |
| 90 | 3 | 0.0% | 0.0% | n/a |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| injection | 42 | 4.8% | 3 | 3 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 42 | 4.8% | 3 | 3 | 0 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

- ada-paper-ctl [gold on_task, conf 90] Acid-base titration curves.pdf -- Contains only introductory text, not methods section content.
- ada-sheet-ctl [gold on_task, conf 90] Titration data.numbers -- Data shows measurements, not experimental methodology details.
- ada-video-ctl [gold on_task, conf 90] How to read a burette - YouTube -- Instructions about burette reading aren't methods for lab reports.

## Missed off-task (gold off_task, predicted otherwise)

none
