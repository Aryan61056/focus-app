# Eval run: fm_swift:relation | text=full | rules=on

scenarios: 47 | text mode: full | rules: on | stages: {'model': 43, 'rule': 2, 'sensitive': 2}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 100.0% (2 of 2) | [34-100%] | >= 97% | yes |
| Off-task precision, lenient (only gold on_task counts) | 100.0% | [34-100%] | >= 97% | yes |
| Recall, clear distractions | 20.0% (of 10) | [6-51%] | >= 85% | no |
| Recall, all off-task | 13.3% (of 15) | [4-38%] | n/a | |
| Accuracy, 3-way | 51.1% | | n/a | |
| False nudges on gold on_task | 0.0% | | | |
| Calibration error (stated confidence, n=2) | 0.000 | | < 0.05 | yes |
| Model latency p50 / p95 | 1882 / 2392 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 15 | 2 | 0 |
| unsure | 8 | 7 | 0 |
| off_task | 9 | 4 | 2 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 2 | 100.0% | 100.0% | 20.0% |
| 50 | 2 | 100.0% | 100.0% | 20.0% |
| 70 | 2 | 100.0% | 100.0% | 20.0% |
| 80 | 2 | 100.0% | 100.0% | 20.0% |
| 90 | 2 | 100.0% | 100.0% | 20.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 4 | 75.0% | 0 | 0 | 1 |
| ai_assistants | 3 | 33.3% | 0 | 0 | 1 |
| messaging | 4 | 25.0% | 0 | 0 | 0 |
| neutral_nav | 4 | 75.0% | 0 | 0 | 0 |
| project_rules | 7 | 57.1% | 1 | 0 | 2 |
| social | 5 | 20.0% | 0 | 0 | 3 |
| web | 8 | 50.0% | 0 | 0 | 2 |
| work_apps | 7 | 57.1% | 0 | 0 | 3 |
| youtube | 5 | 60.0% | 1 | 0 | 1 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 19 | 57.9% | 2 | 0 | 8 |
| gray | 28 | 46.4% | 0 | 0 | 5 |

## Refusals and errors: 3 (counted as unsure)
- f-soc-02: error: May contain sensitive content
- f-soc-03: error: May contain sensitive content
- f-ctx-03: error: May contain sensitive content

## False nudges (predicted off_task, gold is not)

none

## Missed off-task (gold off_task, predicted otherwise)

- f-web-02 [pred on_task, conf n/a] Best budget headphones 2026 | TechRadar -- URL is product review page, not API documentation
- f-web-05 [pred on_task, conf n/a] Cheap flights to Lisbon | Skyscanner -- search results page unrelated to cover letter writing
- f-yt-05 [pred unsure, conf n/a] Top 10 Fails of the Week - YouTube -- not related to organic chemistry or reaction mechanisms
- f-soc-01 [pred on_task, conf n/a] (3) Home / X -- shows social media trends unrelated to API pagination
- f-soc-02 [pred unsure, conf n/a] r/memes - Reddit -- 
- f-soc-05 [pred unsure, conf n/a] TikTok - Make Your Day -- not related to onboarding screens for habit tracker app
- f-wrk-03 [pred on_task, conf n/a] README.md - hobby-game -- documentation for a hobby game project, unrelated to pagination bug
- f-wrk-05 [pred on_task, conf n/a] Library - Civilization VI -- game info page unrelated to quarterly sales review preparation
- f-wrk-07 [pred unsure, conf n/a] Grocery list -- not related to organic chemistry or reaction mechanisms
- f-ai-02 [pred on_task, conf n/a] ChatGPT - Dinner ideas -- Provides recipe suggestions unrelated to pagination bug
- f-ctx-02 [pred on_task, conf n/a] Sourdough starter guide | King Arthur -- URL is unrelated; serves as general cooking reference
- f-ctx-04 [pred on_task, conf n/a] Best hiking trails in Colorado - AllTrails -- URL is for outdoor recreation, unrelated to tax returns
- f-inj-01 [pred on_task, conf n/a] Free movie streaming -- Shows unrelated content; not about pagination or API issues
