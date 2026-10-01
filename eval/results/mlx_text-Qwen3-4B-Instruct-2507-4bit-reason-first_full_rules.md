# Eval run: mlx_text:Qwen3-4B-Instruct-2507-4bit:reason-first | text=full | rules=on

scenarios: 70 | text mode: full | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 50.0% (20 of 40) | [35-65%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 85.0% | [71-93%] | >= 97% | no |
| Recall, clear distractions | 100.0% (of 15) | [80-100%] | >= 85% | yes |
| Recall, all off-task | 100.0% (of 20) | [84-100%] | n/a | |
| Accuracy, 3-way | 70.0% | | n/a | |
| False nudges on gold on_task | 18.8% | | | |
| Calibration error (stated confidence, n=67) | 0.285 | | < 0.05 | no |
| Model latency p50 / p95 | 1935 / 2429 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 26 | 0 | 6 |
| unsure | 1 | 3 | 14 |
| off_task | 0 | 0 | 20 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 40 | 50.0% | 85.0% | 100.0% |
| 50 | 40 | 50.0% | 85.0% | 100.0% |
| 70 | 40 | 50.0% | 85.0% | 100.0% |
| 80 | 40 | 50.0% | 85.0% | 100.0% |
| 90 | 40 | 50.0% | 85.0% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 85.7% | 3 | 1 | 0 |
| ai_assistants | 6 | 83.3% | 3 | 1 | 0 |
| messaging | 8 | 62.5% | 4 | 3 | 0 |
| neutral_nav | 7 | 42.9% | 4 | 3 | 0 |
| project_rules | 6 | 66.7% | 3 | 2 | 0 |
| social | 7 | 71.4% | 4 | 2 | 0 |
| web | 10 | 80.0% | 8 | 2 | 0 |
| work_apps | 11 | 72.7% | 6 | 3 | 0 |
| youtube | 8 | 62.5% | 5 | 3 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 90.2% | 19 | 4 | 0 |
| gray | 29 | 41.4% | 21 | 16 | 0 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

- adv-02 [gold on_task, conf 100] Idempotent requests | Stripe API Reference -- Docs on idempotency, not bug fix
- ai-04 [gold unsure, conf 95] ChatGPT -- off-task
- msg-04 [gold unsure, conf 100] All unreads | Acme | Slack -- Slack unread count, not bug fix
- msg-06 [gold unsure, conf 100] Mom -- no budget or finance mention
- msg-08 [gold on_task, conf 95] Q3 budget review - Chat | Microsoft Teams -- Discussing budget review, not preparing spreadsheet
- nav-01 [gold unsure, conf 100] Start Page -- No homework help available
- nav-06 [gold unsure, conf 100] Deep Focus - Spotify -- Spotify unrelated to blog post
- nav-07 [gold on_task, conf 95] Calculator -- Calculator shows exponential, not integration
- lnk-04 [gold on_task, conf 100] Pricing | Cal.com -- Pricing page not for blog content
- lnk-05 [gold unsure, conf 95] Pricing | Cal.com -- Pricing page lacks launch blog content
- soc-04 [gold unsure, conf 100] r/programming - Reddit -- Discusses programming topics, not bug fixing
- soc-06 [gold unsure, conf 95] Home / X -- No product launch content visible
- web-05 [gold unsure, conf 100] Amazon.com: 7-in-1 USB-C Hub Adapter -- Shopping page, not design tool
- web-06 [gold unsure, conf 100] Fed signals September rate cut - The New York Times -- Article unrelated to budget spreadsheet
- ide-03 [gold unsure, conf 100] .zshrc - dotfiles -- No code or bug fix related to payments
- ide-04 [gold on_task, conf 95] npm test -- checkout.spec.ts - payments-service - zsh -- Test fails due to duplicate charge
- ide-07 [gold unsure, conf 100] Trending repositories on GitHub today -- No payment or bug fixing mentioned
- yt-04 [gold unsure, conf 100] YouTube -- No integration by parts content shown
- yt-05 [gold on_task, conf 95] Trigonometric Substitution Explained - Calculus 2 - YouTube -- Discusses trig sub, not integration by parts
- yt-06 [gold unsure, conf 95] lofi hip hop radio - beats to relax/study to - YouTube -- background music for studying

## Missed off-task (gold off_task, predicted otherwise)

none
