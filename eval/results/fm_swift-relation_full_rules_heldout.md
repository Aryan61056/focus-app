# Eval run: fm_swift:relation | text=full | rules=on

scenarios: 30 | text mode: full | rules: on | stages: {'model': 28, 'rule': 2}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 100.0% (1 of 1) | [21-100%] | >= 97% | yes |
| Off-task precision, lenient (only gold on_task counts) | 100.0% | [21-100%] | >= 97% | yes |
| Recall, clear distractions | 14.3% (of 7) | [3-51%] | >= 85% | no |
| Recall, all off-task | 10.0% (of 10) | [2-40%] | n/a | |
| Accuracy, 3-way | 46.7% | | n/a | |
| False nudges on gold on_task | 0.0% | | | |
| Calibration error (stated confidence, n=2) | 0.000 | | < 0.05 | yes |
| Model latency p50 / p95 | 1962 / 2221 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 10 | 3 | 0 |
| unsure | 4 | 3 | 0 |
| off_task | 5 | 4 | 1 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 1 | 100.0% | 100.0% | 14.3% |
| 50 | 1 | 100.0% | 100.0% | 14.3% |
| 70 | 1 | 100.0% | 100.0% | 14.3% |
| 80 | 1 | 100.0% | 100.0% | 14.3% |
| 90 | 1 | 100.0% | 100.0% | 14.3% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 3 | 33.3% | 0 | 0 | 1 |
| ai_assistants | 2 | 0.0% | 0 | 0 | 1 |
| messaging | 3 | 66.7% | 0 | 0 | 1 |
| neutral_nav | 3 | 100.0% | 0 | 0 | 0 |
| project_rules | 3 | 100.0% | 1 | 0 | 0 |
| social | 3 | 33.3% | 0 | 0 | 1 |
| web | 4 | 0.0% | 0 | 0 | 2 |
| work_apps | 5 | 60.0% | 0 | 0 | 2 |
| youtube | 4 | 25.0% | 0 | 0 | 1 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 19 | 52.6% | 1 | 0 | 6 |
| gray | 11 | 36.4% | 0 | 0 | 3 |

## Refusals and errors: 7 (counted as unsure)
- h-adv-01: error: May contain sensitive content
- h-ai-01: error: May contain sensitive content
- h-nav-01: error: May contain sensitive content
- h-nav-03: error: May contain sensitive content
- h-web-01: error: May contain sensitive content
- h-yt-01: error: May contain sensitive content
- h-yt-02: error: May contain sensitive content

## False nudges (predicted off_task, gold is not)

none

## Missed off-task (gold off_task, predicted otherwise)

- h-adv-01 [pred unsure, conf n/a] Celebrity Gossip Daily -- 
- h-ai-02 [pred on_task, conf n/a] Write a poem about autumn - Claude -- Tool provides inspiration, not investor pitch content
- h-msg-02 [pred on_task, conf n/a] meme-dump | Physics Club -- channel for sharing physics-related jokes and memes
- h-soc-03 [pred unsure, conf n/a] TikTok - Make Your Day -- not related to investor pitch deck or Series A
- h-web-02 [pred on_task, conf n/a] Hotels in Barcelona - Booking.com -- search results page unrelated to lab report task
- h-web-04 [pred on_task, conf n/a] IMDb Top 250 Movies -- shows search results for entertainment task, not settings
- h-app-02 [pred on_task, conf n/a] GameEngine.kt - SpaceShooter -- Shows code unrelated to Android app settings or dark mode
- h-app-04 [pred unsure, conf n/a] Birthday slideshow.key -- Not related to investor pitch deck or Series A work
- h-yt-02 [pred unsure, conf n/a] Minecraft Hardcore: Day 100 - YouTube -- 
