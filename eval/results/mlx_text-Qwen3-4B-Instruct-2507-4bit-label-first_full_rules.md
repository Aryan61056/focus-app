# Eval run: mlx_text:Qwen3-4B-Instruct-2507-4bit:label-first | text=full | rules=on

scenarios: 70 | text mode: full | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 48.8% (20 of 41) | [34-64%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 82.9% | [69-91%] | >= 97% | no |
| Recall, clear distractions | 100.0% (of 15) | [80-100%] | >= 85% | yes |
| Recall, all off-task | 100.0% (of 20) | [84-100%] | n/a | |
| Accuracy, 3-way | 68.6% | | n/a | |
| False nudges on gold on_task | 21.9% | | | |
| Calibration error (stated confidence, n=67) | 0.290 | | < 0.05 | no |
| Model latency p50 / p95 | 2073 / 2711 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 25 | 0 | 7 |
| unsure | 1 | 3 | 14 |
| off_task | 0 | 0 | 20 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 41 | 48.8% | 82.9% | 100.0% |
| 50 | 41 | 48.8% | 82.9% | 100.0% |
| 70 | 41 | 48.8% | 82.9% | 100.0% |
| 80 | 41 | 48.8% | 82.9% | 100.0% |
| 90 | 41 | 48.8% | 82.9% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 85.7% | 3 | 1 | 0 |
| ai_assistants | 6 | 83.3% | 3 | 1 | 0 |
| messaging | 8 | 50.0% | 5 | 4 | 0 |
| neutral_nav | 7 | 42.9% | 4 | 3 | 0 |
| project_rules | 6 | 66.7% | 3 | 2 | 0 |
| social | 7 | 57.1% | 5 | 3 | 0 |
| web | 10 | 80.0% | 8 | 2 | 0 |
| work_apps | 11 | 81.8% | 5 | 2 | 0 |
| youtube | 8 | 62.5% | 5 | 3 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 90.2% | 19 | 4 | 0 |
| gray | 29 | 37.9% | 22 | 17 | 0 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

- adv-02 [gold on_task, conf 100] Idempotent requests | Stripe API Reference -- Docs not about fixing checkout bug
- ai-04 [gold unsure, conf 95] ChatGPT -- No integration by parts visible
- msg-01 [gold on_task, conf 100] payments-eng | Acme | Slack -- Slack thread unrelated to bug fixing
- msg-03 [gold on_task, conf 100] Priya (manager) | Acme | Slack -- Slack message unrelated to bug fixing
- msg-04 [gold unsure, conf 100] All unreads | Acme | Slack -- Slack unrelated to bug fixing
- msg-06 [gold unsure, conf 95] Mom -- No budget or finance content
- nav-01 [gold unsure, conf 100] Start Page -- No integration or homework content
- nav-06 [gold unsure, conf 100] Deep Focus - Spotify -- Spotify music unrelated to blog post
- nav-07 [gold on_task, conf 95] Calculator -- Calculator not for integration by parts
- lnk-04 [gold on_task, conf 95] Pricing | Cal.com -- Pricing page for Cal.com, not Orbit
- lnk-05 [gold unsure, conf 100] Pricing | Cal.com -- Pricing page not for blog writing
- soc-03 [gold on_task, conf 100] r/ExperiencedDevs: How do you handle idempotency when payment webhooks retry? : r/ExperiencedDevs -- Discusses idempotency, not duplicate-charge bug fix
- soc-04 [gold unsure, conf 95] r/programming - Reddit -- No mention of payments or bugs
- soc-06 [gold unsure, conf 95] Home / X -- No product launch blog content
- web-05 [gold unsure, conf 95] Amazon.com: 7-in-1 USB-C Hub Adapter -- Shopping page unrelated to design task
- web-06 [gold unsure, conf 95] Fed signals September rate cut - The New York Times -- News article unrelated to budget spreadsheet
- ide-03 [gold unsure, conf 100] .zshrc - dotfiles -- No code or payment flow related
- ide-07 [gold unsure, conf 100] Trending repositories on GitHub today -- No connection to payments or bug fixing
- yt-04 [gold unsure, conf 100] YouTube -- No integration by parts content
- yt-05 [gold on_task, conf 95] Trigonometric Substitution Explained - Calculus 2 - YouTube -- Discusses trig sub, not integration by parts
- yt-06 [gold unsure, conf 95] lofi hip hop radio - beats to relax/study to - YouTube -- Music for study unrelated to math homework

## Missed off-task (gold off_task, predicted otherwise)

none
