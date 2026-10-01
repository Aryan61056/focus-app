# Eval run: mlx_vlm:Qwen3-VL-4B-Instruct-4bit:reason-first | text=pixels | rules=on

scenarios: 70 | text mode: pixels | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 52.6% (20 of 38) | [37-68%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 86.8% | [73-94%] | >= 97% | no |
| Recall, clear distractions | 100.0% (of 15) | [80-100%] | >= 85% | yes |
| Recall, all off-task | 100.0% (of 20) | [84-100%] | n/a | |
| Accuracy, 3-way | 71.4% | | n/a | |
| False nudges on gold on_task | 15.6% | | | |
| Calibration error (stated confidence, n=67) | 0.240 | | < 0.05 | no |
| Model latency p50 / p95 | 6762 / 7884 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 27 | 0 | 5 |
| unsure | 2 | 3 | 13 |
| off_task | 0 | 0 | 20 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 38 | 52.6% | 86.8% | 100.0% |
| 50 | 38 | 52.6% | 86.8% | 100.0% |
| 70 | 38 | 52.6% | 86.8% | 100.0% |
| 80 | 38 | 52.6% | 86.8% | 100.0% |
| 90 | 38 | 52.6% | 86.8% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 100.0% | 2 | 0 | 0 |
| ai_assistants | 6 | 83.3% | 3 | 1 | 0 |
| messaging | 8 | 75.0% | 3 | 2 | 0 |
| neutral_nav | 7 | 42.9% | 4 | 3 | 0 |
| project_rules | 6 | 66.7% | 3 | 2 | 0 |
| social | 7 | 71.4% | 4 | 2 | 0 |
| web | 10 | 70.0% | 9 | 3 | 0 |
| work_apps | 11 | 81.8% | 5 | 2 | 0 |
| youtube | 8 | 50.0% | 5 | 3 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 97.6% | 16 | 1 | 0 |
| gray | 29 | 34.5% | 22 | 17 | 0 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

- ai-04 [gold unsure, conf 95] ChatGPT -- Not homework help page
- msg-04 [gold unsure, conf 90] All unreads | Acme | Slack -- No payment bug fix context
- msg-06 [gold unsure, conf 100] Mom -- No budget or finance-related content
- nav-01 [gold unsure, conf 90] Start Page -- No math or homework visible
- nav-06 [gold unsure, conf 95] Deep Focus - Spotify -- Spotify music player, not blog post
- nav-07 [gold on_task, conf 95] Calculator -- Calculator not for integration by parts
- lnk-04 [gold on_task, conf 95] Pricing | Cal.com -- Pricing page not relevant to blog post
- lnk-05 [gold unsure, conf 95] Pricing | Cal.com -- Pricing page not relevant to blog post
- soc-04 [gold unsure, conf 95] r/programming - Reddit -- Reddit thread unrelated to payments bug
- soc-06 [gold unsure, conf 95] Home / X -- Not relevant to blog post
- web-05 [gold unsure, conf 100] Amazon.com: 7-in-1 USB-C Hub Adapter -- Amazon product page, not Figma
- web-06 [gold unsure, conf 95] Fed signals September rate cut - The New York Times -- Finance news not budgeting
- web-10 [gold on_task, conf 95] Mobile onboarding flows - Dribbble -- Dribbble shows design examples, not Figma
- ide-03 [gold unsure, conf 100] .zshrc - dotfiles -- Not related to payments or bug fixing
- ide-07 [gold unsure, conf 95] Trending repositories on GitHub today -- No payment bug fix context
- yt-04 [gold unsure, conf 95] YouTube -- YouTube not relevant to calc homework
- yt-05 [gold on_task, conf 95] Trigonometric Substitution Explained - Calculus 2 - YouTube -- Not integration by parts
- yt-08 [gold on_task, conf 95] Idempotency Keys in Payment APIs - Conference Talk - YouTube -- Conference talk on idempotency keys

## Missed off-task (gold off_task, predicted otherwise)

none
