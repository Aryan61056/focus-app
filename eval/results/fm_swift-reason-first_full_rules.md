# Eval run: fm_swift:reason-first | text=full | rules=on

scenarios: 70 | text mode: full | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 50.0% (19 of 38) | [35-65%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 84.2% | [70-93%] | >= 97% | no |
| Recall, clear distractions | 100.0% (of 15) | [80-100%] | >= 85% | yes |
| Recall, all off-task | 95.0% (of 20) | [76-99%] | n/a | |
| Accuracy, 3-way | 57.1% | | n/a | |
| False nudges on gold on_task | 18.8% | | | |
| Calibration error (stated confidence, n=67) | 0.298 | | < 0.05 | no |
| Model latency p50 / p95 | 2278 / 2470 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 16 | 10 | 6 |
| unsure | 0 | 5 | 13 |
| off_task | 0 | 1 | 19 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 38 | 50.0% | 84.2% | 100.0% |
| 50 | 38 | 50.0% | 84.2% | 100.0% |
| 70 | 38 | 50.0% | 84.2% | 100.0% |
| 80 | 38 | 50.0% | 84.2% | 100.0% |
| 90 | 38 | 50.0% | 84.2% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 71.4% | 4 | 2 | 0 |
| ai_assistants | 6 | 83.3% | 3 | 1 | 0 |
| messaging | 8 | 62.5% | 2 | 1 | 0 |
| neutral_nav | 7 | 42.9% | 4 | 3 | 0 |
| project_rules | 6 | 66.7% | 3 | 2 | 0 |
| social | 7 | 42.9% | 6 | 4 | 0 |
| web | 10 | 80.0% | 8 | 2 | 0 |
| work_apps | 11 | 27.3% | 4 | 2 | 1 |
| youtube | 8 | 50.0% | 4 | 2 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 70.7% | 19 | 4 | 0 |
| gray | 29 | 37.9% | 19 | 15 | 1 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

- adv-02 [gold on_task, conf 95] Idempotent requests | Stripe API Reference -- API concept irrelevant to payments-service checkout bug
- adv-06 [gold on_task, conf 90] Integración por partes - ejemplos resueltos - YouTube -- Shows integration by parts examples, not homework problems.
- ai-04 [gold unsure, conf 95] ChatGPT -- Not a calculator or integration resource page.
- msg-06 [gold unsure, conf 95] Mom -- Text is personal conversation, not budgeting information.
- nav-01 [gold unsure, conf 90] Start Page -- Not a learning platform with integration by parts problems.
- nav-06 [gold unsure, conf 90] Deep Focus - Spotify -- Playing music unrelated to product launch planning.
- nav-07 [gold on_task, conf 90] Calculator -- Shows exponential value, not integration by parts problems.
- lnk-04 [gold on_task, conf 90] Pricing | Cal.com -- Shows competitor pricing unrelated to product launch planning
- lnk-05 [gold unsure, conf 90] Pricing | Cal.com -- Page shows pricing info, not launch planning tools.
- soc-01 [gold on_task, conf 90] r/neuroscience on Reddit: New meta-analysis links sleep spindles to memory consolidation -- Reddit post discusses sleep spindles and memory correlation, not systematic review.
- soc-03 [gold on_task, conf 90] r/ExperiencedDevs: How do you handle idempotency when payment webhooks retry? : r/ExperiencedDevs -- Discusses idempotency, unrelated to payment-service checkout.
- soc-04 [gold unsure, conf 95] r/programming - Reddit -- Discussion forum not related to payments-service checkout.
- soc-06 [gold unsure, conf 95] Home / X -- Page shows unrelated social media content, not blog content.
- web-05 [gold unsure, conf 95] Amazon.com: 7-in-1 USB-C Hub Adapter -- Page shows product listing, not design tools.
- web-06 [gold unsure, conf 95] Fed signals September rate cut - The New York Times -- Article discusses Fed policy, unrelated to budgeting.
- ide-03 [gold unsure, conf 95] .zshrc - dotfiles -- Shell script file unrelated to payments-service checkout.
- ide-07 [gold unsure, conf 95] Trending repositories on GitHub today -- Not related to payments-service checkout or duplicate-charge.
- yt-04 [gold unsure, conf 90] YouTube -- Channel promotes unrelated math content, not homework help.
- yt-06 [gold unsure, conf 95] lofi hip hop radio - beats to relax/study to - YouTube -- Playing music unrelated to calculus integration by parts.

## Missed off-task (gold off_task, predicted otherwise)

- ide-02 [pred unsure, conf 50] app.py - pokemon-tracker -- Code shows payment logic, not checkout bug details.
