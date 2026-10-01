# Eval run: fm_swift:label-first | text=full | rules=on

scenarios: 70 | text mode: full | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 51.4% (19 of 37) | [36-67%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 89.2% | [75-96%] | >= 97% | no |
| Recall, clear distractions | 100.0% (of 15) | [80-100%] | >= 85% | yes |
| Recall, all off-task | 95.0% (of 20) | [76-99%] | n/a | |
| Accuracy, 3-way | 68.6% | | n/a | |
| False nudges on gold on_task | 12.5% | | | |
| Calibration error (stated confidence, n=67) | 0.238 | | < 0.05 | no |
| Model latency p50 / p95 | 2197 / 2478 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 25 | 3 | 4 |
| unsure | 0 | 4 | 14 |
| off_task | 0 | 1 | 19 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 37 | 51.4% | 89.2% | 100.0% |
| 50 | 37 | 51.4% | 89.2% | 100.0% |
| 70 | 37 | 51.4% | 89.2% | 100.0% |
| 80 | 37 | 51.4% | 89.2% | 100.0% |
| 90 | 37 | 51.4% | 89.2% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 85.7% | 2 | 0 | 0 |
| ai_assistants | 6 | 83.3% | 3 | 1 | 0 |
| messaging | 8 | 75.0% | 3 | 2 | 0 |
| neutral_nav | 7 | 57.1% | 4 | 3 | 0 |
| project_rules | 6 | 66.7% | 3 | 2 | 0 |
| social | 7 | 57.1% | 4 | 2 | 0 |
| web | 10 | 70.0% | 8 | 2 | 0 |
| work_apps | 11 | 72.7% | 4 | 2 | 1 |
| youtube | 8 | 50.0% | 6 | 4 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 95.1% | 16 | 1 | 0 |
| gray | 29 | 31.0% | 21 | 17 | 1 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

- ai-04 [gold unsure, conf 95] ChatGPT -- Not a math problem-solving platform
- msg-04 [gold unsure, conf 95] All unreads | Acme | Slack -- Not a support or debugging interface
- msg-06 [gold unsure, conf 95] Mom -- Personal messages not related to budgeting
- nav-01 [gold unsure, conf 95] Start Page -- Not a learning platform or integration resource
- nav-06 [gold unsure, conf 95] Deep Focus - Spotify -- Playing music, not writing blog content
- nav-07 [gold on_task, conf 90] Calculator -- Not related to integration by parts problems.
- lnk-04 [gold on_task, conf 95] Pricing | Cal.com -- Shows competitor's pricing, not Orbit product details
- lnk-05 [gold unsure, conf 95] Pricing | Cal.com -- Shows pricing info, not launch details
- soc-04 [gold unsure, conf 95] r/programming - Reddit -- Reddit post discusses programming, not payments.
- soc-06 [gold unsure, conf 95] Home / X -- Not related to product launch content.
- web-05 [gold unsure, conf 95] Amazon.com: 7-in-1 USB-C Hub Adapter -- Not related to design or onboarding tasks
- web-06 [gold unsure, conf 95] Fed signals September rate cut - The New York Times -- Not related to budgeting or finance planning
- ide-03 [gold unsure, conf 95] .zshrc - dotfiles -- Shell script file unrelated to payments bug
- ide-07 [gold unsure, conf 95] Trending repositories on GitHub today -- Not related to payments-service checkout
- yt-04 [gold unsure, conf 90] YouTube -- Channel promotes unrelated calculus content.
- yt-05 [gold on_task, conf 90] Trigonometric Substitution Explained - Calculus 2 - YouTube -- Topic is substitution, not integration by parts problems
- yt-06 [gold unsure, conf 95] lofi hip hop radio - beats to relax/study to - YouTube -- Playing music for studying, not educational content
- yt-08 [gold on_task, conf 90] Idempotency Keys in Payment APIs - Conference Talk - YouTube -- Discusses idempotency, not checkout duplicate-charge fixes

## Missed off-task (gold off_task, predicted otherwise)

- ide-05 [pred unsure, conf 50] Board.swift - DungeonDash -- Code shows game structure, not checkout flow.
