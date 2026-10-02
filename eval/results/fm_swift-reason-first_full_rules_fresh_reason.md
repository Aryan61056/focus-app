# Eval run: fm_swift:reason-first | text=full | rules=on

scenarios: 47 | text mode: full | rules: on | stages: {'model': 43, 'rule': 2, 'sensitive': 2}

## Headline (per moment, no confidence threshold)

| Metric | Value | 95% CI | Target | Met |
|---|---|---|---|---|
| Off-task precision, strict (gold unsure counts as false nudge) | 50.0% (15 of 30) | [33-67%] | >= 97% | no |
| Off-task precision, lenient (only gold on_task counts) | 86.7% | [70-95%] | >= 97% | no |
| Recall, clear distractions | 100.0% (of 10) | [72-100%] | >= 85% | yes |
| Recall, all off-task | 100.0% (of 15) | [80-100%] | n/a | |
| Accuracy, 3-way | 57.4% | | n/a | |
| False nudges on gold on_task | 23.5% | | | |
| Calibration error (stated confidence, n=44) | 0.319 | | < 0.05 | no |
| Model latency p50 / p95 | 2160 / 5668 ms | | text judge < 2000 ms | no |

## Confusion (rows gold, columns predicted)

| gold \ pred | on_task | unsure | off_task |
|---|---|---|---|
| on_task | 9 | 4 | 4 |
| unsure | 1 | 3 | 11 |
| off_task | 0 | 0 | 15 |

## Confidence threshold sweep (a call counts as confirmed only above the threshold)

| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| 0 | 30 | 50.0% | 86.7% | 100.0% |
| 50 | 30 | 50.0% | 86.7% | 100.0% |
| 70 | 30 | 50.0% | 86.7% | 100.0% |
| 80 | 30 | 50.0% | 86.7% | 100.0% |
| 90 | 30 | 50.0% | 86.7% | 100.0% |

## Per category

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| adversarial_misc | 4 | 75.0% | 1 | 0 | 0 |
| ai_assistants | 3 | 66.7% | 2 | 1 | 0 |
| messaging | 4 | 0.0% | 3 | 3 | 0 |
| neutral_nav | 4 | 0.0% | 4 | 4 | 0 |
| project_rules | 7 | 85.7% | 4 | 1 | 0 |
| social | 5 | 60.0% | 4 | 1 | 0 |
| web | 8 | 50.0% | 6 | 4 | 0 |
| work_apps | 7 | 71.4% | 3 | 0 | 0 |
| youtube | 5 | 80.0% | 3 | 1 | 0 |

## Clear vs gray

| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |
|---|---|---|---|---|---|
| clear | 19 | 78.9% | 11 | 1 | 0 |
| gray | 28 | 42.9% | 19 | 14 | 0 |

## Refusals and errors: 1 (counted as unsure)
- f-soc-03: error: May contain sensitive content

## False nudges (predicted off_task, gold is not)

- f-web-01 [gold on_task, conf 90] Pagination | Django REST framework -- Discusses pagination patterns, not API bug fixes.
- f-web-03 [gold on_task, conf 90] Why does my Python loop skip items? - Stack Overflow -- Question discusses loop skipping, not pagination.
- f-web-07 [gold on_task, conf 90] How to write a cover letter that gets read | Indeed -- Contains generic writing tips, not specific Lumen product designer guidance.
- f-web-08 [gold unsure, conf 90] Design Twitter: top portfolio trends 2026 -- Not about product design trends or cover letters.
- f-yt-03 [gold unsure, conf 95] Lofi beats to study to - YouTube -- Playing music unrelated to sales presentation preparation
- f-soc-04 [gold unsure, conf 95] LinkedIn Feed -- Not related to onboarding screens or habit tracking.
- f-msg-01 [gold unsure, conf 95] Mom -- Message app shows personal conversation, not API debugging interface
- f-msg-02 [gold unsure, conf 95] Family group -- Message exchange not related to API pagination.
- f-msg-04 [gold unsure, conf 90] Inbox (14) -- Email contains unrelated business update and personal message.
- f-nav-01 [gold unsure, conf 90] Downloads -- Shows file list, not API pagination tools
- f-nav-02 [gold unsure, conf 90] New Tab -- Not a development environment or API documentation page
- f-nav-03 [gold unsure, conf 90] Wi-Fi -- Settings page unrelated to API pagination.
- f-nav-04 [gold unsure, conf 95] Discover Weekly -- Playlist interface unrelated to reaction mechanisms.
- f-ai-03 [gold unsure, conf 95] Claude -- Interface is asking for help, not providing historical information.
- f-ctx-01 [gold on_task, conf 90] Attention Is All You Need | arXiv -- Transformer paper irrelevant to speech recognition efficiency.

## Missed off-task (gold off_task, predicted otherwise)

none
