# S1: accuracy eval harness

Question: can a local model judge "is this window on task?" well enough to nudge people without crying wolf?
A wrong nudge costs more trust than a missed distraction, so the headline metric is off-task precision.

Everything here is synthetic. No real screen is captured. Python is stdlib only (system 3.9 works).

## Run

```bash
python3 -m unittest discover -s eval/tests
python3 eval/run_eval.py --validate
python3 eval/run_eval.py --backend oracle                  # must be 100%: checks the harness
python3 eval/run_eval.py --backend fm_swift                # Apple on-device system model
python3 eval/run_eval.py --backend fm_swift --text-mode titles   # no window text
python3 eval/run_eval.py --backend fm_swift --no-rules     # every scenario reaches the model
python3 eval/run_eval.py --backend fm_swift --order relation   # judge classifies how the window relates; code maps to a verdict
python3 eval/run_eval.py --backend fm_swift --text-mode ocr    # judge from OCR of a synthetic screenshot
python3 eval/run_eval.py --scenarios eval/scenarios_heldout --tag heldout --backend fm_swift   # held-out set
python3 eval/combine_results.py <run-a.json> <run-b.json>      # two-judge rule from two saved runs
```
Use `--tag` when running a subset or another set, or the result files overwrite the full-run files.

`fm_swift` compiles `swift/fmjudge/main.swift` with `swiftc` on first use (about 2 s) into `.build/`.

## Scenario format

`scenarios/*.json` are JSON arrays. One object is one moment.

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Unique, e.g. `yt-03` |
| `category` | yes | Matches the file name |
| `difficulty` | yes | `clear` (most people agree) or `gray` (reasonable people differ, or the content is subtle) |
| `task` | yes | What the user said they are working on |
| `app`, `window_title` | yes | Foreground app and window title |
| `url`, `document_path`, `window_text` | no | Browser URL, open document path, visible text (short) |
| `label` | yes | Gold: `on_task`, `unsure` or `off_task` |
| `notes` | yes | Why this label. Gray cases say what makes them gray |
| `project` | no | `context`, `linked_domains`, `linked_paths`, `always_allow_apps/domains`, `always_off_apps/domains` |
| `tags` | no | `injection`, `sensitive`, `i18n` |

### Labelling policy (the gold labels encode this)

- `on_task`: the main content serves the task, or it is a normal supporting tool or reference. Adjacent topics from the same course or codebase count.
- `off_task`: the main content is clearly a different activity or a different project. Same site as on-task work does not matter; the page does.
- `unsure`: neutral surfaces (new tab, file browser, settings, empty chat, mixed home feeds, music players), personal messages, and pages in the same field that do not mention the task.
- Sensitive windows (password manager, banking, private window) are `unsure`: the pipeline must not read them.
- Project rules are the owner's decisions, so a rule overrides content (`lnk-06` is on_task because the user said LinkedIn is fine).

This is one person's policy. Several gray labels are debatable. Nobody else has reviewed them.

## Sets

- `scenarios/`: dev set. Used while tuning prompts and settings.
- `scenarios_heldout/`: held-out set. Run only after a prompt is frozen. Once a change follows a held-out run, that set is spent.

## Pipeline under test

```
stage 0  sensitive window (password manager, bank, private window)  -> unsure, never sent to the model
stage 1  project rules (always allow/off, linked domains and paths) -> deterministic verdict
stage 3  text judge (Apple system model, greedy decoding, guided generation)
```

Stage 2 (embedding relevance) is not built. Stage 4 (a vision-language model on pixels) is blocked until Xcode 27 or an approved MLX model; see `docs/S1-accuracy.md`. `--text-mode ocr` covers the screenshot-to-OCR path only, using `swift/shotgen`, which renders synthetic PNGs into the gitignored `.cache/`.
Use `--no-rules` to measure the model alone; the default measures the pipeline.

## Metrics

Per moment, one scenario is one prediction. See `focus_eval/metrics.py`.

- **Off-task precision, strict**: of moments predicted `off_task`, the share that are gold `off_task`. A gold `unsure` predicted `off_task` counts as a false nudge.
- **Off-task precision, lenient**: only a gold `on_task` predicted `off_task` counts as a false nudge.
- **Recall on clear distractions**: gold `off_task` with `difficulty: clear` that were flagged.
- **Calibration error**: expected calibration error of the model's stated confidence. Noisy at this sample size.
- **Wilson 95% intervals** on every proportion. With about 20 off-task moments, an observed 100% still has a lower bound near 84%. No run here can certify the 97% target.
- Not measured yet: time to off-topic timer and to nudge, and false nudges per 3 hours. Those need event sequences and the brain's smoothing.

A model refusal or error is recorded and counted as `unsure`.
