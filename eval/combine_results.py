#!/usr/bin/env python3
"""Score the two-judge combination from two saved result files.

  python3 eval/combine_results.py results/<reason-first run>.json results/<relation run>.json

Rule (frozen after the dev runs, scored once on the held-out set): a moment is confirmed off_task only when the
first judge says off_task AND the second judge does not say on_task. A first-judge on_task stays on_task;
anything else is unsure.
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from focus_eval import metrics  # noqa: E402


def combine(first: dict, second: dict) -> list:
    rows = []
    for sid, r in first.items():
        row = dict(r, confidence=None)
        if r.get("error") or second[sid].get("error"):
            row["pred"] = "unsure"  # a refusal on either judge never confirms a distraction
        elif r["pred"] == "off_task" and second[sid]["pred"] != "on_task":
            row["pred"] = "off_task"
        elif r["pred"] == "on_task":
            row["pred"] = "on_task"
        else:
            row["pred"] = "unsure"
        rows.append(row)
    return rows


def main() -> int:
    args = sys.argv[1:]
    skip_dir = None
    if "--skip-never-judged" in args:  # model the shipped pipeline: never-judged windows never reach the model
        i = args.index("--skip-never-judged"); skip_dir = args[i + 1]; del args[i:i + 2]
    if len(args) != 2:
        print(__doc__)
        return 1
    load = lambda p: {r["id"]: r for r in json.load(open(p))["results"]}  # noqa: E731
    rows = combine(load(args[0]), load(args[1]))
    if skip_dir:
        from focus_eval import rules, scenarios
        by_id = {s.id: s for s in scenarios.load_dir(skip_dir)}
        skipped = [r["id"] for r in rows if r["id"] in by_id and rules.stage1(by_id[r["id"]]) is None and rules.is_never_judged(by_id[r["id"]])]
        for r in rows:
            if r["id"] in skipped:
                r["pred"] = "unsure"
        print("never-judged list applied before the model: %d scenarios left alone (%s)" % (len(skipped), ", ".join(skipped)))
    h = metrics.headline(rows)
    pct = lambda x: "n/a" if x is None else "%.0f%%" % (100 * x)  # noqa: E731
    print("flagged %d (true %d, false on_task %d, false unsure %d)" % (h["flagged"], h["tp"], h["fp_on_task"], h["fp_unsure"]))
    print("precision strict %s %s | lenient %s %s" % (
        pct(h["precision_strict"]), metrics.wilson(h["tp"], h["flagged"]) if h["flagged"] else "",
        pct(h["precision_lenient"]), ""))
    print("recall clear %s (of %d) | all %s (of %d)" % (
        pct(h["recall_clear"]), h["gold_off_task_clear"], pct(h["recall_all"]), h["gold_off_task"]))
    print("accuracy %s" % pct(metrics.accuracy(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
