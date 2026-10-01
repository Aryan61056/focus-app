#!/usr/bin/env python3
"""How well does embedding distance separate the labels? Reports the distribution and threshold trade-offs on dev.

  python3 eval/embed_analysis.py
"""
from __future__ import annotations

import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from focus_eval import embed, rules, scenarios  # noqa: E402


def load(path):
    # Only moments that would reach a model: sensitive windows and project rules are decided before stage 2.
    return [s for s in scenarios.load_dir(path) if not rules.is_sensitive(s) and not rules.stage1(s)]


def auc(pos, neg):
    """Probability a random `pos` distance is larger than a random `neg` one (1.0 = perfect separation)."""
    wins = sum((p > n) + 0.5 * (p == n) for p in pos for n in neg)
    return wins / (len(pos) * len(neg))


def main():
    dev = load(os.path.join(HERE, "scenarios"))
    for with_text in (False, True):
        d = embed.distances(dev, with_text)
        by = {lab: [d[s.id] for s in dev if s.label == lab] for lab in scenarios.LABELS}
        print("== description: %s  (n=%d)" % ("app+title+url+text" if with_text else "app+title+url", len(dev)))
        for lab in scenarios.LABELS:
            v = by[lab]
            print("  %-9s n=%2d  mean %.3f  median %.3f  min %.3f  max %.3f" % (
                lab, len(v), statistics.mean(v), statistics.median(v), min(v), max(v)))
        print("  AUC off_task vs on_task: %.2f | off_task vs unsure: %.2f | unsure vs on_task: %.2f" % (
            auc(by["off_task"], by["on_task"]), auc(by["off_task"], by["unsure"]), auc(by["unsure"], by["on_task"])))
        print("  threshold: flag off_task when distance >= t")
        print("    t      flagged  true  strict   lenient  recall_clear")
        clear_off = [s for s in dev if s.label == "off_task" and s.difficulty == "clear"]
        for t in (0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2):
            flagged = [s for s in dev if d[s.id] >= t]
            tp = sum(s.label == "off_task" for s in flagged)
            fp_on = sum(s.label == "on_task" for s in flagged)
            n = len(flagged)
            rc = sum(d[s.id] >= t for s in clear_off) / len(clear_off)
            print("    %.2f   %3d     %3d   %5s   %5s    %4.0f%%" % (
                t, n, tp, "n/a" if not n else "%.0f%%" % (100 * tp / n), "n/a" if not n else "%.0f%%" % (100 * (n - fp_on) / n), 100 * rc))


if __name__ == "__main__":
    main()
