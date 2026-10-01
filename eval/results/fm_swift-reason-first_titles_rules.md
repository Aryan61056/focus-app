# Eval run: fm_swift:reason-first | text=titles | rules=on

scenarios: 70 | text mode: titles | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 42.9% (18 of 42) | [29-58%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 71.4% | [56-83%] | >= 97% | no |
| Recall, clear distractions | 100.0% (of 15) | [80-100%] | >= 85% | yes |
| Recall, all off-task | 90.0% (of 20) | [70-97%] | n/a | |
| Accuracy, 3-way | 51.4% | | n/a | |
| False nudges on gold on_task | 37.5% | | | |
| Calibration error (stated confidence, n=67) | 0.360 | | < 0.05 | no |
| Model latency p50 / p95 | 2188 / 2283 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 12 | 8 | 12 |
| unsure | 0 | 6 | 12 |
| off_task | 0 | 2 | 18 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 42 | 42.9% | 71.4% | 100.0% |
| 50 | 42 | 42.9% | 71.4% | 100.0% |
| 70 | 42 | 42.9% | 71.4% | 100.0% |
| 80 | 42 | 42.9% | 71.4% | 100.0% |
| 90 | 42 | 42.9% | 71.4% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 71.4% | 4 | 2 | 0 |
| ai_assistants | 6 | 66.7% | 3 | 1 | 0 |
| messaging | 8 | 12.5% | 5 | 4 | 0 |
| neutral_nav | 7 | 42.9% | 4 | 3 | 0 |
| project_rules | 6 | 66.7% | 3 | 2 | 0 |
| social | 7 | 57.1% | 5 | 3 | 0 |
| web | 10 | 70.0% | 8 | 2 | 0 |
| work_apps | 11 | 36.4% | 4 | 3 | 2 |
| youtube | 8 | 50.0% | 6 | 4 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 63.4% | 23 | 8 | 0 |
| gray | 29 | 34.5% | 19 | 16 | 2 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

- adv-02 [gold on_task, conf 90] Idempotent requests | Stripe API Reference -- Discusses idempotency, unrelated to checkout duplicate-charge.
- adv-06 [gold on_task, conf 90] Integración por partes - ejemplos resueltos - YouTube -- Video shows integration by parts examples, not homework problems.
- ai-04 [gold unsure, conf 95] ChatGPT -- Not a calculator or integration by parts resource.
- msg-03 [gold on_task, conf 90] Priya (manager) | Acme | Slack -- Title shows unrelated workspace, not payments-service checkout.
- msg-04 [gold unsure, conf 95] All unreads | Acme | Slack -- Not related to payments-service checkout or duplicate-charge.
- msg-05 [gold on_task, conf 90] Order #88213 not received - Inbox - Mail -- Email about missing order is not a support ticket.
- msg-06 [gold unsure, conf 95] Mom -- Messages app not related to budgeting or spreadsheets
- nav-01 [gold unsure, conf 95] Start Page -- Not a math problem page, just browser favorites page.
- nav-06 [gold unsure, conf 95] Deep Focus - Spotify -- Window promotes music, not product launch content.
- nav-07 [gold on_task, conf 90] Calculator -- Calculator app shows no integration by parts problems.
- lnk-04 [gold on_task, conf 90] Pricing | Cal.com -- Shows competitor pricing unrelated to product launch planning
- lnk-05 [gold unsure, conf 90] Pricing | Cal.com -- Page shows pricing information, not product launch details.
- soc-01 [gold on_task, conf 90] r/neuroscience on Reddit: New meta-analysis links sleep spindles to memory consolidation -- Reddit post discusses sleep spindles and memory, not systematic review.
- soc-03 [gold on_task, conf 95] r/ExperiencedDevs: How do you handle idempotency when payment webhooks retry? : r/ExperiencedDevs -- Discusses idempotency, unrelated to payment bugs.
- soc-04 [gold unsure, conf 95] r/programming - Reddit -- Reddit forum not related to payments-service checkout.
- web-05 [gold unsure, conf 95] Amazon.com: 7-in-1 USB-C Hub Adapter -- Page shows product details, not design tools.
- web-06 [gold unsure, conf 90] Fed signals September rate cut - The New York Times -- Article discusses Fed rate cuts, unrelated to budgeting.
- ide-03 [gold unsure, conf 90] .zshrc - dotfiles -- File browsing unrelated to payments-service checkout.
- ide-04 [gold on_task, conf 90] npm test -- checkout.spec.ts - payments-service - zsh -- Command is unrelated to payments-service checkout debugging.
- ide-07 [gold unsure, conf 95] Trending repositories on GitHub today -- Not related to payments-service checkout or duplicate-charge.
- yt-01 [gold on_task, conf 90] Integration by Parts - Full Lecture | MIT 18.01SC - YouTube -- Video explains integration by parts concepts, not problems.
- yt-05 [gold on_task, conf 90] Trigonometric Substitution Explained - Calculus 2 - YouTube -- Video discusses substitution, not integration by parts problems.
- yt-06 [gold unsure, conf 95] lofi hip hop radio - beats to relax/study to - YouTube -- Playing music unrelated to integration by parts homework.
- yt-08 [gold on_task, conf 90] Idempotency Keys in Payment APIs - Conference Talk - YouTube -- Not about payments-service checkout or duplicate-charge solutions

## Missed off-task (gold off_task, predicted otherwise)

- ide-02 [pred unsure, conf 50] app.py - pokemon-tracker -- File shows code, not payments-service checkout details.
- ide-05 [pred unsure, conf 50] Board.swift - DungeonDash -- File shows code, not payments-service checkout details.
