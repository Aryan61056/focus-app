# Eval run: fm_swift:relation | text=full | rules=on

scenarios: 70 | text mode: full | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 100.0% (5 of 5) | [57-100%] | >= 97% | yes |
| Off-task precision, lenient (only gold on_task counts) | 100.0% | [57-100%] | >= 97% | yes |
| Recall, clear distractions | 33.3% (of 15) | [15-58%] | >= 85% | no |
| Recall, all off-task | 25.0% (of 20) | [11-47%] | n/a | |
| Accuracy, 3-way | 61.4% | | n/a | |
| False nudges on gold on_task | 0.0% | | | |
| Calibration error (stated confidence, n=4) | 0.000 | | < 0.05 | yes |
| Model latency p50 / p95 | 1990 / 2222 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 32 | 0 | 0 |
| unsure | 12 | 6 | 0 |
| off_task | 9 | 6 | 5 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 5 | 100.0% | 100.0% | 33.3% |
| 50 | 5 | 100.0% | 100.0% | 33.3% |
| 70 | 5 | 100.0% | 100.0% | 33.3% |
| 80 | 5 | 100.0% | 100.0% | 33.3% |
| 90 | 5 | 100.0% | 100.0% | 33.3% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 85.7% | 1 | 0 | 1 |
| ai_assistants | 6 | 50.0% | 0 | 0 | 2 |
| messaging | 8 | 75.0% | 0 | 0 | 1 |
| neutral_nav | 7 | 57.1% | 0 | 0 | 1 |
| project_rules | 6 | 83.3% | 1 | 0 | 0 |
| social | 7 | 42.9% | 0 | 0 | 2 |
| web | 10 | 40.0% | 1 | 0 | 5 |
| work_apps | 11 | 54.5% | 0 | 0 | 3 |
| youtube | 8 | 75.0% | 2 | 0 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 75.6% | 5 | 0 | 10 |
| gray | 29 | 41.4% | 0 | 0 | 5 |

## Refusals and errors: 1 (counted as unsure)
- web-06: error: May contain sensitive content

## False nudges (predicted off_task, gold is not)

none

## Missed off-task (gold off_task, predicted otherwise)

- adv-01 [pred unsure, conf n/a] Funny Cat Pictures - 9GAG -- not related to integration by parts homework
- ai-02 [pred on_task, conf n/a] Plan a 5-day trip to Lisbon - ChatGPT -- Shows travel planning, unrelated to payments-service checkout bug
- ai-06 [pred on_task, conf n/a] Write a 1000-word essay on The Great Gatsby - Gemini -- Provides search results for organic chemistry study topic
- msg-02 [pred unsure, conf n/a] random | Acme | Slack -- No content relates to payments-service checkout or duplicate-charge bug
- nav-03 [pred unsure, conf n/a] best pizza near me - Google Search -- Not related to payments-service checkout or duplicate-charge bug
- soc-02 [pred on_task, conf n/a] r/memes - Reddit -- normal tool: search results for the task's adjacent topic
- soc-07 [pred unsure, conf n/a] Instagram -- not related to budgeting or finance tasks
- web-02 [pred on_task, conf n/a] List of Roman emperors - Wikipedia -- historical reference unrelated to sleep and memory literature review
- web-03 [pred unsure, conf n/a] Avengers: Endgame - Wikipedia -- not related to sleep and memory literature review
- web-04 [pred on_task, conf n/a] Logitech G502 Wireless Gaming Mouse - Amazon.com -- Product page unrelated to budgeting or finance tasks
- web-07 [pred on_task, conf n/a] NBA Scores and Schedule - ESPN -- shows sports info unrelated to budgeting task
- web-08 [pred unsure, conf n/a] Library - Steam -- not related to integration by parts homework
- ide-02 [pred on_task, conf n/a] app.py - pokemon-tracker -- Shows code unrelated to payments-service checkout flow
- ide-05 [pred on_task, conf n/a] Board.swift - DungeonDash -- Shows code unrelated to payments-service checkout bug
- ide-10 [pred on_task, conf n/a] Wedding invitation (personal) - Figma -- Shows design assets unrelated to onboarding screens
