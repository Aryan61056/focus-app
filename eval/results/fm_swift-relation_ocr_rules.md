# Eval run: fm_swift:relation | text=ocr | rules=on

scenarios: 70 | text mode: ocr | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 100.0% (4 of 4) | [51-100%] | >= 97% | yes |
| Off-task precision, lenient (only gold on_task counts) | 100.0% | [51-100%] | >= 97% | yes |
| Recall, clear distractions | 26.7% (of 15) | [11-52%] | >= 85% | no |
| Recall, all off-task | 20.0% (of 20) | [8-42%] | n/a | |
| Accuracy, 3-way | 57.1% | | n/a | |
| False nudges on gold on_task | 0.0% | | | |
| Calibration error (stated confidence, n=4) | 0.000 | | < 0.05 | yes |
| Model latency p50 / p95 | 2020 / 2357 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 32 | 0 | 0 |
| unsure | 14 | 4 | 0 |
| off_task | 13 | 3 | 4 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 4 | 100.0% | 100.0% | 26.7% |
| 50 | 4 | 100.0% | 100.0% | 26.7% |
| 70 | 4 | 100.0% | 100.0% | 26.7% |
| 80 | 4 | 100.0% | 100.0% | 26.7% |
| 90 | 4 | 100.0% | 100.0% | 26.7% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 85.7% | 1 | 0 | 1 |
| ai_assistants | 6 | 50.0% | 0 | 0 | 2 |
| messaging | 8 | 62.5% | 0 | 0 | 1 |
| neutral_nav | 7 | 57.1% | 0 | 0 | 1 |
| project_rules | 6 | 83.3% | 1 | 0 | 0 |
| social | 7 | 42.9% | 0 | 0 | 2 |
| web | 10 | 20.0% | 0 | 0 | 6 |
| work_apps | 11 | 54.5% | 0 | 0 | 3 |
| youtube | 8 | 75.0% | 2 | 0 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 73.2% | 4 | 0 | 11 |
| gray | 29 | 34.5% | 0 | 0 | 5 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

none

## Missed off-task (gold off_task, predicted otherwise)

- adv-01 [pred unsure, conf n/a] Funny Cat Pictures - 9GAG -- not related to integration by parts homework
- ai-02 [pred on_task, conf n/a] Plan a 5-day trip to Lisbon - ChatGPT -- Tool provides travel advice, unrelated to payments-service checkout
- ai-06 [pred on_task, conf n/a] Write a 1000-word essay on The Great Gatsby - Gemini -- Provides search results for writing assistance related to the task
- msg-02 [pred on_task, conf n/a] random | Acme | Slack -- channel list is unrelated to payments-service checkout bug
- nav-03 [pred on_task, conf n/a] best pizza near me - Google Search -- search results page unrelated to payments-service checkout bug
- soc-02 [pred on_task, conf n/a] r/memes - Reddit -- Reddit forum posts unrelated to academic literature review
- soc-07 [pred on_task, conf n/a] Instagram -- normal tool: search results for marketing or social media inspiration
- web-02 [pred on_task, conf n/a] List of Roman emperors - Wikipedia -- historical reference unrelated to sleep and memory literature review
- web-03 [pred unsure, conf n/a] Avengers: Endgame - Wikipedia -- not related to sleep and memory literature review
- web-04 [pred on_task, conf n/a] Logitech G502 Wireless Gaming Mouse - Amazon.com -- product page unrelated to budgeting or finance tasks
- web-07 [pred on_task, conf n/a] NBA Scores and Schedule - ESPN -- provides sports information unrelated to budgeting task
- web-08 [pred unsure, conf n/a] Library - Steam -- Not related to integration by parts homework
- web-09 [pred on_task, conf n/a] Play Chess Online - Chess.com -- Tool for distraction, not related to organic chemistry study
- ide-02 [pred on_task, conf n/a] app.py - pokemon-tracker -- code file unrelated to payments-service checkout bug
- ide-05 [pred on_task, conf n/a] Board.swift - DungeonDash -- Shows code unrelated to payments-service checkout bug
- ide-10 [pred on_task, conf n/a] Wedding invitation (personal) - Figma -- Template shows design elements unrelated to onboarding screens
