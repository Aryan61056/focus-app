# Eval run: fm_swift:reason-first | text=ocr | rules=on

scenarios: 70 | text mode: ocr | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 48.8% (20 of 41) | [34-64%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 80.5% | [66-90%] | >= 97% | no |
| Recall, clear distractions | 100.0% (of 15) | [80-100%] | >= 85% | yes |
| Recall, all off-task | 100.0% (of 20) | [84-100%] | n/a | |
| Accuracy, 3-way | 58.6% | | n/a | |
| False nudges on gold on_task | 25.0% | | | |
| Calibration error (stated confidence, n=67) | 0.290 | | < 0.05 | no |
| Model latency p50 / p95 | 2404 / 4642 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 16 | 8 | 8 |
| unsure | 0 | 5 | 13 |
| off_task | 0 | 0 | 20 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 41 | 48.8% | 80.5% | 100.0% |
| 50 | 41 | 48.8% | 80.5% | 100.0% |
| 70 | 41 | 48.8% | 80.5% | 100.0% |
| 80 | 39 | 48.7% | 82.1% | 100.0% |
| 90 | 39 | 48.7% | 82.1% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 71.4% | 4 | 2 | 0 |
| ai_assistants | 6 | 83.3% | 3 | 1 | 0 |
| messaging | 8 | 50.0% | 3 | 2 | 0 |
| neutral_nav | 7 | 28.6% | 5 | 4 | 0 |
| project_rules | 6 | 66.7% | 3 | 2 | 0 |
| social | 7 | 57.1% | 4 | 2 | 0 |
| web | 10 | 80.0% | 8 | 2 | 0 |
| work_apps | 11 | 45.5% | 6 | 3 | 0 |
| youtube | 8 | 50.0% | 5 | 3 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 70.7% | 20 | 5 | 0 |
| gray | 29 | 41.4% | 21 | 16 | 0 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

- adv-02 [gold on_task, conf 95] Idempotent requests | Stripe API Reference -- API concept irrelevant to payments-service checkout debugging
- adv-06 [gold on_task, conf 90] Integración por partes - ejemplos resueltos - YouTube -- Video shows integration by parts examples, not homework problems.
- ai-04 [gold unsure, conf 95] ChatGPT -- Not a calculator or integration resource page.
- msg-06 [gold unsure, conf 95] Mom -- Messages app showing personal conversation, not budgeting info
- msg-07 [gold on_task, conf 90] Calc 2 study group -- Group chat discusses integration by parts problem, not homework problems.
- nav-01 [gold unsure, conf 95] Start Page -- Not a math problem page, just browser start page.
- nav-05 [gold unsure, conf 90] Downloads -- File browser showing unrelated downloads, not budgeting tools.
- nav-06 [gold unsure, conf 90] Deep Focus - Spotify -- Playing music unrelated to product launch planning
- nav-07 [gold on_task, conf 90] Calculator -- Calculator shows exponential value, not integration problems.
- lnk-04 [gold on_task, conf 90] Pricing | Cal.com -- Shows competitor pricing unrelated to product launch planning
- lnk-05 [gold unsure, conf 90] Pricing | Cal.com -- Page shows pricing info, not product launch details.
- soc-03 [gold on_task, conf 90] r/ExperiencedDevs: How do you handle idempotency when payment webhooks retry? : r/ExperiencedDevs -- Discusses idempotency, unrelated to payment-service checkout.
- soc-04 [gold unsure, conf 95] r/programming - Reddit -- Not related to payments-service checkout or duplicate-charge.
- web-05 [gold unsure, conf 90] Amazon.com: 7-in-1 USB-C Hub Adapter -- Page shows product listing, not design tools.
- web-06 [gold unsure, conf 90] Fed signals September rate cut - The New York Times -- Article discusses Fed rate cuts, unrelated to budgeting.
- ide-03 [gold unsure, conf 95] .zshrc - dotfiles -- Shell configuration file unrelated to payments-service checkout.
- ide-07 [gold unsure, conf 95] Trending repositories on GitHub today -- Not related to payments-service checkout or duplicate-charge.
- ide-08 [gold on_task, conf 70] Stripe: duplicate charges on retry - Stack Overflow -- Discusses Stripe duplicate charges, not checkout-specific fix.
- yt-04 [gold unsure, conf 90] YouTube -- Channel promotes unrelated calculus content, not homework help.
- yt-05 [gold on_task, conf 90] Trigonometric Substitution Explained - Calculus 2 - YouTube -- Discusses substitution, not integration by parts techniques.
- yt-06 [gold unsure, conf 95] lofi hip hop radio - beats to relax/study to - YouTube -- Playing music unrelated to calculus integration by parts.

## Missed off-task (gold off_task, predicted otherwise)

none
