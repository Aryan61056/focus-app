#!/usr/bin/env python3
"""Measure memory, CPU and an energy proxy for a judge backend over a simulated session.

  python3 eval/measure_resources.py --backend fm_swift --order relation
  python3 eval/measure_resources.py --backend mlx_text --order relation

Phases (wall-clock): idle baseline -> load -> loaded idle -> N judgments at a fixed cadence -> loaded idle -> unload.
Run it with nothing else heavy going, or the numbers are contaminated.

Energy: `top -stats power` gives macOS's energy-impact score per process, no sudo needed. It is a relative
score, not watts. For real CPU/GPU/ANE power run, in your own terminal:
  sudo powermetrics --samplers cpu_power,gpu_power,ane_power -i 1000 -n 120
Apple's system model runs in system daemons, not in our process, so the report also shows which other
processes' memory and power changed against the idle baseline.
Stdlib only.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from focus_eval import backends, prompts, scenarios  # noqa: E402

UNITS = {"B": 1, "K": 1024, "M": 1024 ** 2, "G": 1024 ** 3}


def to_bytes(text: str) -> float:
    m = re.match(r"([\d.]+)([BKMG]?)", text.strip().rstrip("+-"))
    return float(m.group(1)) * UNITS.get(m.group(2) or "B", 1) if m else 0.0


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def system_snapshot() -> dict:
    swap = sh(["sysctl", "-n", "vm.swapusage"])
    used = re.search(r"used = ([\d.]+)M", swap)
    free_pct = re.search(r"free percentage: (\d+)%", sh(["memory_pressure"]))
    vm = sh(["vm_stat"])
    comp = re.search(r"Pages occupied by compressor:\s+(\d+)", vm)
    return {
        "swap_used_mb": float(used.group(1)) if used else None,
        "mem_free_pct": int(free_pct.group(1)) if free_pct else None,
        "compressor_mb": int(comp.group(1)) * 16384 / 1024 ** 2 if comp else None,
    }


def descendants(pid: int) -> list:
    pids = [pid]
    for child in sh(["pgrep", "-P", str(pid)]).split():
        pids.extend(descendants(int(child)))
    return pids


def tree_footprint_mb(pid: int) -> float:
    total = 0.0
    for p in descendants(pid):
        m = re.search(r"Footprint: ([\d.]+) (KB|MB|GB)", sh(["footprint", "-p", str(p)]))
        if m:
            total += float(m.group(1)) * {"KB": 1 / 1024, "MB": 1, "GB": 1024}[m.group(2)]
    return total


def tree_cpu_seconds(pid: int) -> float:
    total = 0.0
    for p in descendants(pid):
        t = sh(["ps", "-o", "time=", "-p", str(p)]).strip()
        if t:
            parts = t.split(":")
            secs = 0.0
            for part in parts:
                secs = secs * 60 + float(part)
            total += secs
    return total


class TopSampler(threading.Thread):
    """Streams `top` once a second and keeps each sample's top processes by energy impact."""

    def __init__(self, n: int = 20):
        super().__init__(daemon=True)
        self.samples = []  # (time, {command: (cpu, mem_bytes, power)})
        self.proc = subprocess.Popen(
            ["top", "-l", "0", "-s", "1", "-o", "power", "-n", str(n), "-stats", "pid,command,cpu,mem,power"],
            stdout=subprocess.PIPE, text=True)

    def run(self):
        current, idx = {}, 0
        for line in self.proc.stdout:
            if line.startswith("PID"):
                if idx >= 2:  # block 0 holds lifetime values, so keep only blocks from index 1 on
                    self.samples.append((time.time(), current))
                current = {}
                idx += 1
                continue
            parts = line.split()
            if idx and len(parts) >= 5:
                try:
                    cmd = " ".join(parts[1:-3])
                    prev = current.get(cmd, (0.0, 0.0, 0.0))
                    power = float(parts[-1])
                    if power < 0:  # top occasionally prints a bogus negative score; ignore it
                        continue
                    current[cmd] = (prev[0] + float(parts[-3]), max(prev[1], to_bytes(parts[-2])), prev[2] + power)
                except ValueError:
                    pass

    def stop(self):
        self.proc.terminate()


def window(samples, t0, t1):
    return [s for t, s in samples if t0 <= t < t1]


def avg_total_power(frames):
    return sum(sum(v[2] for v in f.values()) for f in frames) / len(frames) if frames else None


def by_command(frames):
    acc = defaultdict(lambda: [0.0, 0.0, 0])
    for f in frames:
        for cmd, (cpu, mem, power) in f.items():
            acc[cmd][0] += power
            acc[cmd][1] = max(acc[cmd][1], mem)
            acc[cmd][2] += 1
    n = len(frames) or 1
    return {c: (v[0] / n, v[1]) for c, v in acc.items()}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--backend", default="fm_swift", choices=["fm_swift", "mlx_text"])
    ap.add_argument("--order", default="relation", choices=["reason-first", "label-first", "relation"])
    ap.add_argument("--calls", type=int, default=24)
    ap.add_argument("--interval", type=float, default=10.0, help="seconds between judgments (tightened cadence is 8-10 s)")
    ap.add_argument("--idle", type=float, default=20.0, help="seconds per idle phase")
    ap.add_argument("--out", default=os.path.join(HERE, "results"))
    ap.add_argument("--tag", default="", help="suffix for the result file name")
    args = ap.parse_args()

    items = [s for s in scenarios.load_dir(os.path.join(HERE, "scenarios")) if not s.project and "sensitive" not in s.tags]
    backend = backends.make(args.backend, args.order)
    report = {"backend": backend.name, "calls": args.calls, "interval_s": args.interval}

    sampler = TopSampler()
    sampler.start()
    snap0 = system_snapshot()
    t_idle0 = time.time()
    time.sleep(args.idle)
    t_idle1 = time.time()

    t_load0 = time.time()
    backend.start()
    report["load_s"] = round(time.time() - t_load0, 1)
    pid = backend.proc.pid
    snap_loaded = system_snapshot()
    time.sleep(2)
    report["footprint_after_load_mb"] = round(tree_footprint_mb(pid))

    # first call includes lazy loading for some backends; report separately
    s0 = items[0]
    ins, pr = prompts.build(s0, version=backend.prompt_version)
    t = time.time()
    backend.judge(s0, ins, pr)
    report["first_call_ms"] = round((time.time() - t) * 1000)

    t_loaded0 = time.time()
    time.sleep(args.idle)
    t_loaded1 = time.time()
    report["footprint_loaded_idle_mb"] = round(tree_footprint_mb(pid))

    cpu0 = tree_cpu_seconds(pid)
    lat, peak_fp = [], report["footprint_loaded_idle_mb"]
    t_calls0 = time.time()
    for i in range(args.calls):
        s = items[i % len(items)]
        ins, pr = prompts.build(s, version=backend.prompt_version)
        t = time.time()
        backend.judge(s, ins, pr)
        lat.append((time.time() - t) * 1000)
        peak_fp = max(peak_fp, tree_footprint_mb(pid))
        rest = args.interval - (time.time() - t)
        if rest > 0:
            time.sleep(rest)
    t_calls1 = time.time()
    snap_calls = system_snapshot()
    report["cpu_seconds_per_call_in_process"] = round((tree_cpu_seconds(pid) - cpu0) / args.calls, 2)
    report["footprint_peak_mb"] = round(peak_fp)
    lat.sort()
    report["latency_ms"] = {"p50": round(lat[len(lat) // 2]), "p95": round(lat[int(0.95 * (len(lat) - 1))])}

    t_post0 = time.time()
    time.sleep(args.idle)
    t_post1 = time.time()
    backend.close()
    time.sleep(10)
    snap_end = system_snapshot()
    sampler.stop()

    idle = window(sampler.samples, t_idle0, t_idle1)
    loaded = window(sampler.samples, t_loaded0, t_loaded1)
    calls = window(sampler.samples, t_calls0, t_calls1)
    post = window(sampler.samples, t_post0, t_post1)
    report["energy_impact_total_top20"] = {
        "idle_baseline": avg_total_power(idle), "loaded_idle": avg_total_power(loaded),
        "during_calls": avg_total_power(calls), "loaded_idle_after": avg_total_power(post)}
    base = by_command(idle)
    during = by_command(calls)
    delta = sorted(((during[c][0] - base.get(c, (0, 0))[0], c, during[c][1], base.get(c, (0, 0))[1]) for c in during),
                   reverse=True)[:6]
    report["top_energy_increase_vs_idle"] = [
        {"process": c, "energy_impact_delta": round(d, 1), "mem_mb_during": round(m / 1024 ** 2), "mem_mb_idle": round(b / 1024 ** 2)}
        for d, c, m, b in delta]
    report["system"] = {"before": snap0, "after_load": snap_loaded, "after_calls": snap_calls, "after_unload": snap_end}
    report["samples"] = {"idle": len(idle), "loaded": len(loaded), "calls": len(calls)}
    report["phases_epoch"] = {"idle": [t_idle0, t_idle1], "loaded_idle": [t_loaded0, t_loaded1],
                              "calls": [t_calls0, t_calls1], "loaded_idle_after": [t_post0, t_post1]}

    os.makedirs(args.out, exist_ok=True)
    path = os.path.join(args.out, "resources_%s%s.json" % (backend.name.replace(":", "-"), ("_" + args.tag) if args.tag else ""))
    with open(path, "w") as fh:
        json.dump(report, fh, indent=1)
    print(json.dumps(report, indent=1))
    print("\nsaved", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
