# Eval run: mlx_text:Qwen3-4B-Instruct-2507-4bit:reason-first | text=full | rules=on

scenarios: 30 | text mode: full | rules: on | stages: {'model': 28, 'rule': 2}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 66.7% (10 of 15) | [42-85%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 100.0% | [80-100%] | >= 97% | yes |
| Recall, clear distractions | 100.0% (of 7) | [65-100%] | >= 85% | yes |
| Recall, all off-task | 100.0% (of 10) | [72-100%] | n/a | |
| Accuracy, 3-way | 80.0% | | n/a | |
| False nudges on gold on_task | 0.0% | | | |
| Calibration error (stated confidence, n=30) | 0.182 | | < 0.05 | no |
| Model latency p50 / p95 | 1958 / 2131 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 13 | 0 | 0 |
| unsure | 1 | 1 | 5 |
| off_task | 0 | 0 | 10 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 15 | 66.7% | 100.0% | 100.0% |
| 50 | 15 | 66.7% | 100.0% | 100.0% |
| 70 | 15 | 66.7% | 100.0% | 100.0% |
| 80 | 15 | 66.7% | 100.0% | 100.0% |
| 90 | 15 | 66.7% | 100.0% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 3 | 66.7% | 2 | 1 | 0 |
| ai_assistants | 2 | 100.0% | 1 | 0 | 0 |
| messaging | 3 | 66.7% | 2 | 1 | 0 |
| neutral_nav | 3 | 33.3% | 2 | 2 | 0 |
| project_rules | 3 | 100.0% | 1 | 0 | 0 |
| social | 3 | 66.7% | 2 | 1 | 0 |
| web | 4 | 100.0% | 2 | 0 | 0 |
| work_apps | 5 | 100.0% | 2 | 0 | 0 |
| youtube | 4 | 75.0% | 1 | 0 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 19 | 100.0% | 7 | 0 | 0 |
| gray | 11 | 45.5% | 8 | 5 | 0 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

- h-adv-03 [gold unsure, conf 100] KeePassXC - Passwords -- No lab report content in password app
- h-msg-03 [gold unsure, conf 100] Jordan -- Dinner plans, not pitch deck content
- h-nav-01 [gold unsure, conf 100] New Tab -- No essay content, just search page
- h-nav-03 [gold unsure, conf 100] Classical Focus - Apple Music -- Music unrelated to essay writing
- h-soc-02 [gold unsure, conf 100] r/androiddev - Reddit -- Not related to Android app dark mode

## Missed off-task (gold off_task, predicted otherwise)

none
