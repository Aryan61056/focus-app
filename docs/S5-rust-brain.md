# Spike S5: a Rust brain that matches the Swift brain, called from Swift over a C ABI

Date: 2026-10-01. Scope: the logic port, plus the Mac half of the FFI (Rust called from Swift over a hand-written C ABI). **Not done:** Rust to C# on Windows (no Windows machine here, so nothing about Windows is verified) and UniFFI (it needs crates downloaded, which needs the owner's say-so; the hand-written ABI needs none).

## What exists
- `core/brain-rs/`: the brain in Rust, about 740 lines, **zero dependencies** (no crates downloaded, no I/O, no clock). `cargo run --offline --bin trace -- ../traces` runs the golden traces.
- Both runners have a `--dump` mode (one canonical line per event). `tools/diff_brains.py` generates random event sequences, runs them through the Swift and the Rust brain and compares every effect (numbers to 6 decimals).

## The C ABI (new)
`core/brain-rs/include/focus_brain.h`, implemented in `src/ffi.rs`: `focus_brain_new`, `focus_brain_step(brain, t, event_json) -> effects_json`, `focus_brain_free_string`, `focus_brain_free`. JSON in the golden-trace shape goes in, a JSON array of effects comes out (`src/wire.rs`, `src/json.rs`, no dependencies). A panic inside the brain returns null instead of crossing the boundary. The trace runner uses the same wire layer, so the traces test the real boundary format. `mac/Sources/CFocusBrain` exposes the header to Swift and `brain-ffi-check` links the static library.

## Results (all run, 2026-10-01)
| Check | Result |
|---|---|
| 16 golden traces, Rust | all pass, same event counts as Swift |
| Mutating one constant in the Rust brain | caught by 5 of 16 traces (the runner is real) |
| Differential fuzz, 400 seeded sessions of 900 s, all 15 effect types reached | **400 identical, 400,292 event lines compared, 0 mismatches** |
| **Swift calling Rust over the C ABI** (`brain-ffi-check`), golden traces | 11,590 events, all identical |
| Same, 400 fuzzed sessions | **400,292 events identical**; 1.4 s total for both brains and the JSON round trip, roughly 3.5 microseconds per event |
| Differential fuzz sensitivity: 3 deliberate mutations of the Rust brain | 1 caught (`confirm_after`), 2 not (rate-cap window 600 s to 601 s, persist delay 12 s to 13 s) |

Reading the last row honestly: the fuzzer finds logic differences that show up in effects over ordinary sequences. It is weak against boundaries that need an exact timing (the rate-cap edge) and the persist delay may be unobservable in the effect stream. So "0 mismatches" supports "the port is faithful", not "the two are proven equal".

## What this says about S5
- A shared Rust core is **feasible on the logic side**: the state machine ports line by line, with no surprises, in a few hours of work, and it can be held to the Swift behaviour by traces plus fuzzing.
- Rust to Swift works on this Mac and the boundary cost is negligible next to one event per second. Still open and untested: packaging the library into the app bundle (universal binary, signing), and Rust to C# with P/Invoke on a real Windows machine. The Swift brain stays the reference, and the app still uses it, until the Windows half is proven.
- No crates are needed for any of it, which keeps the engine free of network-capable dependencies.

## Reproduce
```bash
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
(cd core/brain-rs && cargo run --offline -q --bin trace -- ../traces)
python3 tools/diff_brains.py --runs 400 --seed 11
(cd core/brain-rs && cargo build --release --offline -q) && (cd mac && swift run -q brain-ffi-check ../core/traces)
```
