# Eval run: always_unsure | text=full | rules=on

scenarios: 70 | text mode: full | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 100.0% (1 of 1) | [21-100%] | >= 97% | yes |
| Off-task precision, lenient (only gold on_task counts) | 100.0% | [21-100%] | >= 97% | yes |
| Recall, clear distractions | 6.7% (of 15) | [1-30%] | >= 85% | no |
| Recall, all off-task | 5.0% (of 20) | [1-24%] | n/a | |
| Accuracy, 3-way | 31.4% | | n/a | |
| False nudges on gold on_task | 0.0% | | | |
| Calibration error (stated confidence, n=67) | 0.246 | | < 0.05 | no |
| Model latency p50 / p95 | 0 / 0 ms | | text judge < 2000 ms | yes |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 3 | 29 | 0 |
| unsure | 0 | 18 | 0 |
| off_task | 0 | 19 | 1 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 1 | 100.0% | 100.0% | 6.7% |
| 50 | 1 | 100.0% | 100.0% | 6.7% |
| 70 | 1 | 100.0% | 100.0% | 6.7% |
| 80 | 1 | 100.0% | 100.0% | 6.7% |
| 90 | 1 | 100.0% | 100.0% | 6.7% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 42.9% | 0 | 0 | 2 |
| ai_assistants | 6 | 16.7% | 0 | 0 | 2 |
| messaging | 8 | 25.0% | 0 | 0 | 1 |
| neutral_nav | 7 | 42.9% | 0 | 0 | 1 |
| project_rules | 6 | 83.3% | 1 | 0 | 0 |
| social | 7 | 28.6% | 0 | 0 | 2 |
| web | 10 | 20.0% | 0 | 0 | 6 |
| work_apps | 11 | 18.2% | 0 | 0 | 3 |
| youtube | 8 | 25.0% | 0 | 0 | 2 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 7.3% | 1 | 0 | 14 |
| gray | 29 | 65.5% | 0 | 0 | 5 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

none

## Missed off-task (gold off_task, predicted otherwise)

- adv-01 [pred unsure, conf 50] Funny Cat Pictures - 9GAG -- never nudges
- adv-07 [pred unsure, conf 50] Cómo hacer tortilla española | Receta fácil - YouTube -- never nudges
- ai-02 [pred unsure, conf 50] Plan a 5-day trip to Lisbon - ChatGPT -- never nudges
- ai-06 [pred unsure, conf 50] Write a 1000-word essay on The Great Gatsby - Gemini -- never nudges
- msg-02 [pred unsure, conf 50] random | Acme | Slack -- never nudges
- nav-03 [pred unsure, conf 50] best pizza near me - Google Search -- never nudges
- soc-02 [pred unsure, conf 50] r/memes - Reddit -- never nudges
- soc-07 [pred unsure, conf 50] Instagram -- never nudges
- web-02 [pred unsure, conf 50] List of Roman emperors - Wikipedia -- never nudges
- web-03 [pred unsure, conf 50] Avengers: Endgame - Wikipedia -- never nudges
- web-04 [pred unsure, conf 50] Logitech G502 Wireless Gaming Mouse - Amazon.com -- never nudges
- web-07 [pred unsure, conf 50] NBA Scores and Schedule - ESPN -- never nudges
- web-08 [pred unsure, conf 50] Library - Steam -- never nudges
- web-09 [pred unsure, conf 50] Play Chess Online - Chess.com -- never nudges
- ide-02 [pred unsure, conf 50] app.py - pokemon-tracker -- never nudges
- ide-05 [pred unsure, conf 50] Board.swift - DungeonDash -- never nudges
- ide-10 [pred unsure, conf 50] Wedding invitation (personal) - Figma -- never nudges
- yt-02 [pred unsure, conf 50] Cat fails jump #shorts - YouTube -- never nudges
- yt-03 [pred unsure, conf 50] Top 10 Funniest Fails of 2026 (Try Not To Laugh) - YouTube -- never nudges
