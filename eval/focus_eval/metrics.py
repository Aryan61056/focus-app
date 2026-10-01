"""Section 9.3 metrics, computed per moment (one scenario = one moment).

Per-moment scoring is not the same as the per-episode "false nudges per 3 hours" target.
Episode-level metrics need sequences and the brain's smoothing, so they come later.
"""
from __future__ import annotations

import math
from collections import Counter, defaultdict
from typing import Dict, Iterable, List, Optional, Tuple

LABELS = ("on_task", "unsure", "off_task")


def wilson(k: int, n: int, z: float = 1.96) -> Tuple[float, float]:
    """95% Wilson interval for a proportion. (0, 1) when n == 0."""
    if n == 0:
        return 0.0, 1.0
    p = k / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return max(0.0, centre - half), min(1.0, centre + half)


def _ratio(k: int, n: int) -> Optional[float]:
    return k / n if n else None


def confirmed_off_task(r: dict, threshold: float) -> bool:
    """A prediction counts as a confirmed off-task call only above the confidence threshold."""
    if r["pred"] != "off_task":
        return False
    conf = r.get("confidence")
    return True if conf is None else conf >= threshold


def headline(results: List[dict], threshold: float = 0.0) -> dict:
    """Precision and recall of confirmed off-task calls.

    strict:  a gold `unsure` predicted off_task is a false nudge (ambiguity should do nothing).
    lenient: only a gold `on_task` predicted off_task is a false nudge.
    """
    flagged = [r for r in results if confirmed_off_task(r, threshold)]
    tp = sum(1 for r in flagged if r["gold"] == "off_task")
    fp_on = sum(1 for r in flagged if r["gold"] == "on_task")
    fp_unsure = sum(1 for r in flagged if r["gold"] == "unsure")
    n = len(flagged)
    gold_off = [r for r in results if r["gold"] == "off_task"]
    gold_clear = [r for r in gold_off if r["difficulty"] == "clear"]
    hit_all = sum(1 for r in gold_off if confirmed_off_task(r, threshold))
    hit_clear = sum(1 for r in gold_clear if confirmed_off_task(r, threshold))
    return {
        "threshold": threshold,
        "flagged": n,
        "tp": tp,
        "fp_on_task": fp_on,
        "fp_unsure": fp_unsure,
        "precision_strict": _ratio(tp, n),
        "precision_strict_ci": wilson(tp, n),
        "precision_lenient": _ratio(n - fp_on, n),
        "precision_lenient_ci": wilson(n - fp_on, n),
        "recall_all": _ratio(hit_all, len(gold_off)),
        "recall_all_ci": wilson(hit_all, len(gold_off)),
        "recall_clear": _ratio(hit_clear, len(gold_clear)),
        "recall_clear_ci": wilson(hit_clear, len(gold_clear)),
        "gold_off_task": len(gold_off),
        "gold_off_task_clear": len(gold_clear),
        "false_nudge_rate_on_task": _ratio(fp_on, sum(1 for r in results if r["gold"] == "on_task")),
    }


def accuracy(results: List[dict]) -> Optional[float]:
    return _ratio(sum(1 for r in results if r["pred"] == r["gold"]), len(results))


def confusion(results: List[dict]) -> Dict[str, Dict[str, int]]:
    table = {g: Counter() for g in LABELS}
    for r in results:
        table[r["gold"]][r["pred"]] += 1
    return {g: {p: table[g][p] for p in LABELS} for g in LABELS}


def threshold_sweep(results: List[dict], thresholds: Iterable[float]) -> List[dict]:
    return [headline(results, t) for t in thresholds]


def by_group(results: List[dict], key: str) -> Dict[str, dict]:
    groups = defaultdict(list)
    for r in results:
        groups[r[key]].append(r)
    out = {}
    for name, rs in sorted(groups.items()):
        h = headline(rs)
        out[name] = {
            "n": len(rs),
            "accuracy": accuracy(rs),
            "flagged": h["flagged"],
            "false_nudges": h["fp_on_task"] + h["fp_unsure"],
            "missed_off_task": h["gold_off_task"] - h["tp"],
        }
    return out


def calibration(results: List[dict], bins: int = 5) -> dict:
    """Expected calibration error of the model's stated confidence in its own verdict.

    Needs confidence on every row. Small n makes this noisy; treat as indicative.
    """
    rows = [r for r in results if r.get("confidence") is not None and r["pred"] in LABELS]
    if not rows:
        return {"ece": None, "n": 0, "bins": []}
    buckets: List[List[dict]] = [[] for _ in range(bins)]
    for r in rows:
        idx = min(bins - 1, int(r["confidence"] * bins))
        buckets[idx].append(r)
    ece = 0.0
    detail = []
    for i, b in enumerate(buckets):
        if not b:
            continue
        acc = sum(1 for r in b if r["pred"] == r["gold"]) / len(b)
        conf = sum(r["confidence"] for r in b) / len(b)
        ece += len(b) / len(rows) * abs(acc - conf)
        detail.append({"bin": i, "n": len(b), "mean_conf": conf, "accuracy": acc})
    return {"ece": ece, "n": len(rows), "bins": detail}


def latency(results: List[dict]) -> dict:
    vals = sorted(r["latency_ms"] for r in results if r.get("latency_ms") is not None and r.get("stage") == "model")
    if not vals:
        return {"n": 0}

    def pct(p: float) -> float:
        return vals[min(len(vals) - 1, int(round(p * (len(vals) - 1))))]

    return {"n": len(vals), "p50_ms": pct(0.5), "p95_ms": pct(0.95), "max_ms": vals[-1]}


def stage_mix(results: List[dict]) -> Dict[str, int]:
    return dict(Counter(r["stage"] for r in results))
