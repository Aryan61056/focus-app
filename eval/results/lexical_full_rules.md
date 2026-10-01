# Eval run: lexical | text=full | rules=on

scenarios: 70 | text mode: full | rules: on | stages: {'model': 63, 'sensitive': 3, 'rule': 4}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 50.0% (19 of 38) | [35-65%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 81.6% | [67-91%] | >= 97% | no |
| Recall, clear distractions | 100.0% (of 15) | [80-100%] | >= 85% | yes |
| Recall, all off-task | 95.0% (of 20) | [76-99%] | n/a | |
| Accuracy, 3-way | 67.1% | | n/a | |
| False nudges on gold on_task | 21.9% | | | |
| Calibration error (stated confidence, n=67) | 0.030 | | < 0.05 | yes |
| Model latency p50 / p95 | 0 / 0 ms | | text judge < 2000 ms | yes |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 22 | 3 | 7 |
| unsure | 0 | 6 | 12 |
| off_task | 0 | 1 | 19 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 38 | 50.0% | 81.6% | 100.0% |
| 50 | 38 | 50.0% | 81.6% | 100.0% |
| 70 | 1 | 100.0% | 100.0% | 6.7% |
| 80 | 1 | 100.0% | 100.0% | 6.7% |
| 90 | 1 | 100.0% | 100.0% | 6.7% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 7 | 71.4% | 4 | 2 | 0 |
| ai_assistants | 6 | 83.3% | 3 | 1 | 0 |
| messaging | 8 | 62.5% | 3 | 2 | 0 |
| neutral_nav | 7 | 57.1% | 4 | 3 | 0 |
| project_rules | 6 | 66.7% | 3 | 2 | 0 |
| social | 7 | 71.4% | 4 | 2 | 0 |
| web | 10 | 80.0% | 8 | 2 | 0 |
| work_apps | 11 | 63.6% | 4 | 2 | 1 |
| youtube | 8 | 50.0% | 5 | 3 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 41 | 85.4% | 19 | 4 | 0 |
| gray | 29 | 41.4% | 19 | 15 | 1 |

## Refusals and errors: 0 (counted as unsure)

## False nudges (predicted off_task, gold is not)

- adv-02 [gold on_task, conf 60] Idempotent requests | Stripe API Reference -- no keyword overlap
- adv-06 [gold on_task, conf 60] Integración por partes - ejemplos resueltos - YouTube -- no keyword overlap
- ai-04 [gold unsure, conf 60] ChatGPT -- no keyword overlap
- msg-05 [gold on_task, conf 60] Order #88213 not received - Inbox - Mail -- no keyword overlap
- msg-06 [gold unsure, conf 60] Mom -- no keyword overlap
- nav-01 [gold unsure, conf 60] Start Page -- no keyword overlap
- nav-06 [gold unsure, conf 60] Deep Focus - Spotify -- no keyword overlap
- nav-07 [gold on_task, conf 60] Calculator -- no keyword overlap
- lnk-04 [gold on_task, conf 60] Pricing | Cal.com -- no keyword overlap
- lnk-05 [gold unsure, conf 60] Pricing | Cal.com -- no keyword overlap
- soc-03 [gold on_task, conf 60] r/ExperiencedDevs: How do you handle idempotency when payment webhooks retry? : r/ExperiencedDevs -- no keyword overlap
- soc-04 [gold unsure, conf 60] r/programming - Reddit -- no keyword overlap
- web-05 [gold unsure, conf 60] Amazon.com: 7-in-1 USB-C Hub Adapter -- no keyword overlap
- web-06 [gold unsure, conf 60] Fed signals September rate cut - The New York Times -- no keyword overlap
- ide-03 [gold unsure, conf 60] .zshrc - dotfiles -- no keyword overlap
- ide-07 [gold unsure, conf 60] Trending repositories on GitHub today -- no keyword overlap
- yt-04 [gold unsure, conf 60] YouTube -- no keyword overlap
- yt-05 [gold on_task, conf 60] Trigonometric Substitution Explained - Calculus 2 - YouTube -- no keyword overlap
- yt-06 [gold unsure, conf 60] lofi hip hop radio - beats to relax/study to - YouTube -- no keyword overlap

## Missed off-task (gold off_task, predicted otherwise)

- ide-10 [pred unsure, conf 50] Wedding invitation (personal) - Figma -- weak overlap
