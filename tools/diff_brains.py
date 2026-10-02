#!/usr/bin/env python3
"""Differential test of the two brains: random event sequences go through the Swift brain and the Rust brain (spike S5),
and every effect on every event must match (numbers to 6 decimals). Reproducible: same --seed, same traces.
Usage: tools/diff_brains.py [--runs 300] [--seed 1] [--seconds 900] [--keep]"""
from __future__ import annotations
import argparse, json, os, random, subprocess, sys, tempfile, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
RUST = ROOT / "core/brain-rs/target/release/trace"
SWIFT = ROOT / "mac/.build/release/brain-trace"
ENV = dict(os.environ, PATH="/opt/homebrew/opt/rustup/bin:" + os.environ["PATH"])

def build() -> None:
    subprocess.run(["cargo", "build", "--release", "--offline", "-q"], cwd=ROOT / "core/brain-rs", env=ENV, check=True)
    env = {k: v for k, v in os.environ.items() if k != "SDKROOT"}
    env["DEVELOPER_DIR"] = subprocess.check_output(["xcode-select", "-p"], text=True).strip()
    subprocess.run(["swift", "build", "-c", "release", "--product", "brain-trace"], cwd=ROOT / "mac", env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

WINDOWS = ["w:a", "w:b", "w:c", "w:d"]
ACTIONS = ["pause", "resume", "snooze", "extend", "dismiss", "panic", "break", "that_was_fine", "mark_relevant", "ignore_window",
           "mark_off_task", "back_to_task", "next_step"]

def judgment(rng, t, window, label, strong_p=0.85):
    j = {"observedAt": round(max(0.0, t - rng.choice([0, 1, 3.5, 3.5, 6])), 3), "windowKey": window,
         "contentKey": "c:" + str(rng.randint(1, 4)), "label": label}
    if label == "off_task" and rng.random() < strong_p: j["strong"] = True
    if rng.random() < 0.05: j["flag"] = rng.choice(["refusal", "error"])
    if rng.random() < 0.03: j["source"] = rng.choice(["rule", "unchanged"])
    if rng.random() < 0.4: j["requestId"] = rng.randint(1, 8)
    return {"Judgment": j}

def special(rng):
    r = rng.random()
    if r < 0.45:
        a = {"action": rng.choice(ACTIONS)}
        if a["action"] in ("snooze", "break", "extend") and rng.random() < 0.8: a["minutes"] = rng.choice([1, 2, 5, 10])
        return {"UserAction": a}
    if r < 0.93: return {rng.choice(["Idle", "Active", "Sleep", "Wake", "MeetingStart", "MeetingEnd", "SensitiveEntered", "SensitiveLeft"]): {}}
    if r < 0.98: return {"PowerChange": {"constrained": rng.random() < 0.5, "critical": rng.random() < 0.2}}
    return {"SessionEnd": {}}

def gen(rng: random.Random, seconds: int) -> dict:
    """Episodes: hold one window for a while with mostly consistent verdicts (so drifts get confirmed, interrupted and
    recovered), plus occasional user actions, holds, power changes and contradicting verdicts."""
    cfg = {"sessionId": "s", "taskId": "task", "mode": rng.choice(["Open", "Timed"]), "preset": rng.choice(["Gentle", "Standard", "Strict"]),
           "shadow": rng.random() < 0.2, "sound": rng.random() < 0.2}
    if cfg["mode"] == "Timed": cfg["durationSeconds"] = rng.choice([300, 600, 1500])
    if rng.random() < 0.3: cfg["reentryPrompt"] = rng.random() < 0.5
    steps = [{"t": 0, "ev": {"SessionStart": cfg}}]
    t = 0.0
    while t < seconds:
        win = rng.choice(WINDOWS)
        kind = rng.choices(["on", "off", "unsure", "mixed"], [0.35, 0.4, 0.1, 0.15])[0]
        w = {"windowKey": win}
        if rng.random() < 0.5: w["siteKey"] = "s:" + rng.choice("xyz")
        if rng.random() < 0.15: w["ruleLabel"] = rng.choice(["on_task", "off_task", "unsure"])
        steps.append({"t": round(t, 3), "ev": {"WindowChange": w}})
        end = t + rng.choice([15, 30, 60, 90, 150, 240])
        while t < min(end, seconds):
            t += rng.choice([4, 8, 10, 10, 12, 20])
            label = {"on": "on_task", "off": "off_task", "unsure": "unsure"}.get(kind) or rng.choice(["on_task", "off_task", "unsure"])
            if rng.random() < 0.07: label = rng.choice(["on_task", "off_task", "unsure"])   # a contradicting verdict
            steps.append({"t": round(t, 3), "ev": judgment(rng, t, win if rng.random() < 0.95 else rng.choice(WINDOWS), label)})
            if rng.random() < 0.06:
                t += rng.choice([0.5, 1, 3]); steps.append({"t": round(t, 3), "ev": special(rng)})
    return {"trace": "fuzz", "steps": steps, "ticks": {"from": 0, "until": seconds}}

def dump(binary: pathlib.Path, path: str, flag: str) -> list:
    out = subprocess.run([str(binary), flag, path], capture_output=True, text=True)
    if out.returncode != 0: return ["CRASH rc=%d %s" % (out.returncode, out.stderr.strip()[:300])]
    return out.stdout.splitlines()

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--runs", type=int, default=300); ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--seconds", type=int, default=900); ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    build()
    rng = random.Random(a.seed); tmp = pathlib.Path(tempfile.mkdtemp(prefix="brains-")); bad = 0; lines = 0
    for n in range(a.runs):
        path = tmp / f"fuzz-{a.seed}-{n}.json"; path.write_text(json.dumps(gen(rng, a.seconds)))
        sw, rs = dump(SWIFT, str(path), "--dump"), dump(RUST, str(path), "--dump")
        lines += len(sw)
        if sw != rs:
            bad += 1
            i = next((k for k, (x, y) in enumerate(zip(sw, rs)) if x != y), min(len(sw), len(rs)))
            print(f"MISMATCH run {n} (seed {a.seed}) at line {i}: {path}")
            print("  swift:", sw[i] if i < len(sw) else "<end>"); print("  rust: ", rs[i] if i < len(rs) else "<end>")
            if bad >= 3: break
    print(f"{a.runs - bad if bad < 3 else n + 1 - bad} identical, {bad} mismatched; {lines} event lines compared; traces in {tmp}")
    return 1 if bad else 0

if __name__ == "__main__": sys.exit(main())
