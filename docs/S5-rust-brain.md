# Spike S5 (part 1): a Rust brain that matches the Swift brain

Date: 2026-10-01. Scope: only the logic port. The FFI half of S5 (Rust to Swift and Rust to C#, built on both OSs) is **not done**: Windows cannot be run here, and UniFFI needs crates downloaded, which needs the owner's say-so.

## What exists
- `core/brain-rs/`: the brain in Rust, about 740 lines, **zero dependencies** (no crates downloaded, no I/O, no clock). `cargo run --offline --bin trace -- ../traces` runs the golden traces.
- Both runners have a `--dump` mode (one canonical line per event). `tools/diff_brains.py` generates random event sequences, runs them through the Swift and the Rust brain and compares every effect (numbers to 6 decimals).

## Results (all run, 2026-10-01)
| Check | Result |
|---|---|
| 16 golden traces, Rust | all pass, same event counts as Swift |
| Mutating one constant in the Rust brain | caught by 5 of 16 traces (the runner is real) |
| Differential fuzz, 400 seeded sessions of 900 s, all 15 effect types reached | **400 identical, 400,292 event lines compared, 0 mismatches** |
| Differential fuzz sensitivity: 3 deliberate mutations of the Rust brain | 1 caught (`confirm_after`), 2 not (rate-cap window 600 s to 601 s, persist delay 12 s to 13 s) |

Reading the last row honestly: the fuzzer finds logic differences that show up in effects over ordinary sequences. It is weak against boundaries that need an exact timing (the rate-cap edge) and the persist delay may be unobservable in the effect stream. So "0 mismatches" supports "the port is faithful", not "the two are proven equal".

## What this says about S5
- A shared Rust core is **feasible on the logic side**: the state machine ports line by line, with no surprises, in a few hours of work, and it can be held to the Swift behaviour by traces plus fuzzing.
- The Swift brain stays the reference until the FFI half is proven. Two risks are still open and untested: the Rust to Swift binding at runtime cost and packaging, and Rust to C# on real Windows.
- If the owner wants to go ahead: the cheapest next step is a hand-written C ABI (`step(json) -> json`) with no crates, then a Swift call from the app and a C# P/Invoke on a Windows machine. That keeps the engine free of network-capable dependencies.

## Reproduce
```bash
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
(cd core/brain-rs && cargo run --offline -q --bin trace -- ../traces)
python3 tools/diff_brains.py --runs 400 --seed 11
```
