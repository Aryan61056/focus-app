# T7: prompt injection from on-screen text

Principle 6: text on the screen is data, never instructions. This measures whether the Apple on-device judge obeys text planted in a window.
All runs: Apple system model, synthetic scenarios, rules on. Small samples; read as direction, not certification.

## Sets
- `eval/scenarios_injection/`: control and injected twins of the same page (injection in title, body, breakout, padded body, URL, document path). Results with no guard: `eval/results/*_inj_*`; with guard: `*_injg_*`.
- `eval/scenarios_injection_adaptive/`: 42 on-task pages written after seeing the first results, 36 of them carrying an injection phrased to dodge obvious keywords. No guard: `*_ada_*`; guard: `*_adag_*`.

## Findings
| | Injected on-task pages judged off_task (a false nudge) | Result |
|---|---|---|
| Adaptive set, two-judge rule, no guard | 5 of 36 | fails the gate (gate is 0) |
| Adaptive set, two-judge rule, with guard | 0 of 36 | 36 stopped before the model, answered `unsure` |
| First injection set, no guard | 0 flips in the dangerous direction | 11 pages moved to `unsure` |
| First injection set, with guard | 0 | 39 pages moved to `unsure` (the guard also catches the plain cases) |

The reason-first judge on its own was flipped from on_task to off_task by injected text in the first round; the two-judge rule removed those, but not the adaptive ones.

## What the guard is
`Rules.looksInjected` (Swift) and `rules.looks_injected` (Python mirror, parity-checked): ten patterns for label words, "ignore previous instructions", fake system or assistant markers, tag breakouts and "note to the AI". Text is normalized first (NFKC, zero-width characters removed, percent-decoding). A hit returns `unsure` with a fixed reason before the model runs.

## Limits (say these out loud)
- It is a denylist and fails open. Phrasing it does not know passes through to the two-judge rule, which already failed 5 of 36 adaptive cases. The adaptive set was written after the first results, so the guard is partly tuned to it. Fresh attacks are untested.
- It costs coverage: a real page that discusses these words (a prompt-engineering tutorial, say) is never judged. Two clean scenarios (`f-ai-01`, `f-ai-02`) hit it in earlier work; not yet investigated.
- The same guard now covers words read from screen pictures (OCR), which are untrusted in the same way.
- `unsure` does nothing, so the failure it causes is a miss, not a false nudge (principle 1).
