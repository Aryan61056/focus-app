# S1: accuracy eval, first results

Date: 2026-10-01 · Machine: M1 Pro, 16 GB, macOS 27.0 · Model: Apple on-device system model (FoundationModels, SDK 26.5, greedy decoding)

**Bottom line.** The on-device system model, used as a single-pass judge, does not come close to the 97% precision target. It also has no usable confidence signal. A two-judge combination removes false nudges on genuinely on-task work, but still flags ambiguous moments and catches only about 60% of clear distractions. Nothing here is enough to certify any target, because there are only 20 off-task moments (10 in the held-out set).

## What was built

| Piece | Where | Status |
|---|---|---|
| 100 synthetic scenarios: 70 dev (`eval/scenarios/`), 30 held-out (`eval/scenarios_heldout/`) | JSON, schema in `eval/README.md` | validated by 29 unit tests |
| Runner and reports (precision strict and lenient, recall, calibration, latency, per-category, Wilson CIs) | `eval/run_eval.py`, `eval/focus_eval/` | run: oracle scores 100% |
| Stage 0 (sensitive windows) and stage 1 (project rules) | `eval/focus_eval/rules.py` | run, unit-tested |
| Stage 3 text judge: Apple system model via a Swift helper | `eval/swift/fmjudge/` | run |
| Screenshot path: synthetic render plus Apple Vision OCR, fed to the same judge | `eval/swift/shotgen/` | run |
| Stage 2 (embedding relevance) | | **not built** |
| Stage 4 (vision-language judge on pixels) | | **blocked**: FoundationModels in SDK 26.5 has no image input (needs Xcode 27) |
| `fm` CLI backend | | **not used**: needs `sudo fm license` (legal terms), which you haven't agreed to. The framework route gives the same model without it |

Windows: nothing written or run.

## Numbers

Dev set: 70 moments, 20 gold off-task (15 clear). **Strict** counts a gold `unsure` predicted `off_task` as a false nudge (ambiguity should do nothing). **Lenient** counts only a gold `on_task` predicted `off_task`. 95% intervals are wide, see the end.

| Run | Flagged off-task | Precision strict | Precision lenient | Recall clear | 3-way accuracy | False nudges on gold on-task |
|---|---|---|---|---|---|---|
| Always unsure (floor) | 1 | 100% (1 of 1) | 100% | 6.7% | 31% | 0% |
| Keyword overlap (floor) | 38 | 50% | 82% | 100% | 67% | 22% |
| Apple model, reason-first, full text | 38 | 50% | 84% | 100% | 57% | 19% |
| Apple model, label-first, full text | 37 | 51% | 89% | 100% | 69% | 12.5% |
| Apple model, reason-first, titles only (no window text) | 42 | 43% | 71% | 100% | 51% | 37.5% |
| Apple model, reason-first, rules off | 42 | 45% | 83% | 100% | 50% | 22% |
| Apple model, relation judge (below) | 5 | 100% (5 of 5) | 100% | 33% | 61% | 0% |
| **Two-judge: reason-first says off AND relation does not say on** | 14 | 79% (11 of 14) | 100% | 67% | 60% | 0% |
| Same two-judge rule, judged from OCR of synthetic screenshots | 8 | 88% (7 of 8) | 100% | 47% | 57% | 0% |

**Held-out set** (30 moments, 10 gold off-task, 7 clear). Run once, after the prompts and the two-judge rule were frozen:

| Run | Flagged | Precision strict | Precision lenient | Recall clear |
|---|---|---|---|---|
| Reason-first | 19 | 53% | 84% | 100% |
| Relation judge | 1 | 100% (1 of 1) | 100% | 14% |
| Two-judge rule | 7 | 71% (5 of 7) | 100% | 57% |

Single-judge results matched the dev set, so the prompts are not obviously overfit. The held-out set is now spent for these prompts. Further tuning needs fresh scenarios.

Other measured numbers:

- **Latency**: p50 about 2.2 s, p95 about 2.5 s per call (target: text judge under 2 s). The two-judge rule needs two calls, so about 4.5 s unless they run in parallel. These are wall times including pipe overhead. Some runs overlapped with my other work, so treat them as approximate.
- **Calibration error**: 0.30 (reason-first), 0.24 (label-first); target under 0.05. The model reports 90 to 95 confidence on nearly every call, right or wrong, so the confidence threshold sweep changes nothing.
- **Refusals and guardrail errors**: 0 across all runs.
- **Window text matters**: dropping it (titles only) cut lenient precision from 84% to 71%.
- **Rules matter**: they resolved 7 of 70 scenarios deterministically. Turning them off lowers accuracy from 57% to 50%.
- **Stage mix**: not meaningful against the 80/15/5 target. The scenario set is made of hard cases, not typical traffic.

## What I found

1. **The model over-flags.** It answers `off_task` for almost anything that doesn't mention the task. It turns "neutral" moments (new tab, music, personal message, empty chat, mixed feed) into off-task calls about 70% of the time, despite explicit rules and a "when in doubt, unsure" instruction.
2. **A keyword-overlap baseline matches it on precision.** Single-pass Apple model precision (50% strict, 84% lenient) is the same as counting shared words between the task and the window. At this size the system model adds little beyond lexical overlap, though it is better when window text is available.
3. **Its fine-grained field is unreliable.** In the relation run the model wrote reasons like "unrelated to the task" and still chose `supporting`. The stated reason is more trustworthy than the category it picks. That made the relation judge very conservative (5 flags, 33% recall) rather than accurate.
4. **Combining two differently framed judges helps precision but costs recall.** It removes every false nudge on genuinely on-task work (lenient 100% on both sets), but still flags 3 of 18 `unsure` moments on dev and 2 of 7 on held-out: music and personal messages.
5. **The system model gives no confidence signal.** The 26.5 SDK has no log-probs API, and verbal confidence is uninformative. That makes plan feature B4 (calibrated confidence from log-probs) impossible with this model. Alternatives are agreement across several calls or a different model.
6. **It hallucinated on some inputs.** For `ide-02` it said "code shows payment logic" about a Pokémon card tracker.
7. **Context window is about 4K tokens.** Window text is capped at 1,200 characters.

## What I'm unsure about

- **Sample size.** 20 off-task moments on dev, 10 held-out. Even a perfect run can't prove 97%: 20 of 20 has a lower bound near 84%. The 79% strict figure for the two-judge rule has an interval of roughly 52% to 92%.
- **One labeler.** The gold labels are my policy, written in `eval/README.md`, and nobody else has reviewed them. Strict precision depends heavily on whether a moment is `unsure` or `off_task`. Several gray labels are debatable (personal messages, music, banter channels). Your relabeling of the gray cases would be the single most useful input.
- **Synthetic is cleaner than real.** Window text here is short and tidy. Real accessibility or OCR text is noisier and longer, which could lower accuracy.
- **The two-judge rule was chosen after looking at dev.** The held-out run supports it (lenient 100%, 7 flagged), but with tiny numbers.
- **Run-to-run variance is not measured.** Decoding is greedy, but I haven't repeated a run to check stability.
- **Per-moment, not per-episode.** The real targets (false nudges per 3 hours, time to nudge) need event sequences and the brain's smoothing. The two judges' errors are probably correlated, so requiring "two independent verdicts" in the brain may be less protective than it looks.
- **The OCR path is a weak proxy for vision.** Clean synthetic render, plain text. It exercises screenshot to OCR to text, not a vision-language model reading thumbnails and layout.

## Recommendation

1. **Don't build on the single-pass system model alone.** Treat model verdicts as weak evidence and make project rules, linked resources, user corrections and shadow mode (plan B15, currently P1 but already default in L6) do the heavy lifting. This supports the plan's direction, and I'd make shadow mode P0.
2. **Next in S1, needs your OK (see below):** run a stronger local text model through the same harness (an MLX Qwen3-class model) to see whether the gap is the model or the task framing. Also run the system model with image input once Xcode 27 is available.
3. **Then:** add an episode-level simulator (sequences, smoothing, the brain's two-verdict rule) so the real targets can be measured, and grow the dataset, ideally with a second labeler.
4. Spike S5 (Rust bindings) and the others don't depend on this and can proceed in parallel when you want.

## Needs your decision

- **Xcode 27** (to test image input in Foundation Models): download size and install need your approval. Not started.
- **MLX models**: nothing downloaded. If you approve, I'd propose a Qwen3 4B-class text model (about 2.5 GB) from Hugging Face's `mlx-community`, and Qwen3-VL-4B (about 3 GB) for vision. I'll confirm exact names, sizes and licenses before any download. Running MLX also needs a Python environment through `uv`, which is another approval.
- **`sudo fm license`**: optional. Not needed for this work.
