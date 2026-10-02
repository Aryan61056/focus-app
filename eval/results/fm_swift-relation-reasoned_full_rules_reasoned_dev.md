# Eval run: fm_swift:relation-reasoned | text=full | rules=on

scenarios: 70 | text mode: full | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 100.0% (7 of 7) | [65-100%] | >= 97% | yes |
| Off-task precision, lenient (only gold on_task counts) | 100.0% | [65-100%] | >= 97% | yes |
| Recall, clear distractions | 40.0% (of 15) | [20-64%] | >= 85% | no |
| Recall, all off-task | 35.0% (of 20) | [18-57%] | n/a | |
| Accuracy, 3-way | 68.6% | | n/a | |
| False nudges on gold on_task | 0.0% | | | |
| Calibration error (stated confidence, n=4) | 0.000 | | < 0.05 | yes |
| Model latency p50 / p95 | 2048 / 4165 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 31 | 1 | 0 |
| unsure | 8 | 10 | 0 |
| off_task | 6 | 7 | 7 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 7 | 100.0% | 100.0% | 40.0% |
| 50 | 7 | 100.0% | 100.0% | 40.0% |
| 70 | 7 | 100.0% | 100.0% | 40.0% |
| 80 | 7 | 100.0% | 100.0% | 40.0% |
| 90 | 7 | 100.0% | 100.0% | 40.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 85.7% | 1 | 0 | 1 |
| ai_assistants | 6 | 66.7% | 0 | 0 | 2 |
| messaging | 8 | 75.0% | 0 | 0 | 1 |
| neutral_nav | 7 | 71.4% | 0 | 0 | 1 |
| project_rules | 6 | 83.3% | 1 | 0 | 0 |
| social | 7 | 28.6% | 0 | 0 | 2 |
| web | 10 | 50.0% | 2 | 0 | 4 |
| work_apps | 11 | 72.7% | 1 | 0 | 2 |
| youtube | 8 | 87.5% | 2 | 0 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 78.0% | 6 | 0 | 9 |
| gray | 29 | 55.2% | 1 | 0 | 4 |

## Refusals and errors: 1 (counted as unsure)
- web-06: error: May contain sensitive content

## False nudges (predicted off_task, gold is not)

none

## Missed off-task (gold off_task, predicted otherwise)

- adv-01 [pred unsure, conf n/a] Funny Cat Pictures - 9GAG -- not related to integration by parts homework
- ai-02 [pred unsure, conf n/a] Plan a 5-day trip to Lisbon - ChatGPT -- Provides unrelated travel suggestions instead of checkout troubleshooting
- ai-06 [pred on_task, conf n/a] Write a 1000-word essay on The Great Gatsby - Gemini -- Discussing literary analysis unrelated to organic chemistry reaction mechanisms
- msg-02 [pred unsure, conf n/a] random | Acme | Slack -- Random messages not related to payments-service checkout
- nav-03 [pred on_task, conf n/a] best pizza near me - Google Search -- Normal search results for unrelated query
- soc-02 [pred on_task, conf n/a] r/memes - Reddit -- normal tool: search results for the task
- soc-07 [pred on_task, conf n/a] Instagram -- normal tool, reference or channel for this kind of work: messages about the task
- web-02 [pred unsure, conf n/a] List of Roman emperors - Wikipedia -- provides historical information unrelated to sleep and memory
- web-03 [pred unsure, conf n/a] Avengers: Endgame - Wikipedia -- provides unrelated movie information for literature review
- web-04 [pred on_task, conf n/a] Logitech G502 Wireless Gaming Mouse - Amazon.com -- normal tool, reference or channel for unrelated product research
- web-08 [pred on_task, conf n/a] Library - Steam -- a normal tool, reference or channel for this kind of work: gaming
- ide-05 [pred unsure, conf n/a] Board.swift - DungeonDash -- Code unrelated to payments-service checkout-flow task
- ide-10 [pred unsure, conf n/a] Wedding invitation (personal) - Figma -- Shows unrelated design assets for a different purpose
