#!/usr/bin/env python3
"""Export the Apple two-judge verdict for every scenario (dev and held-out) for the episode simulator.

  python3 eval/export_verdicts.py

Uses the saved runs (reason-first plus relation) and the combine rule, including the refusal fix.
Output: eval/results/verdicts_two_judge.json (synthetic data only).
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from combine_results import combine  # noqa: E402

R = os.path.join(HERE, "results")
from focus_eval import scenarios as sc  # noqa: E402
SETS = {
    "dev": ("fm_swift-reason-first_full_rules.json", "fm_swift-relation_full_rules.json"),
    "heldout": ("fm_swift-reason-first_full_rules_heldout.json", "fm_swift-relation_full_rules_heldout.json"),
}


def load(name):
    return {r["id"]: r for r in json.load(open(os.path.join(R, name)))["results"]}


def main() -> int:
    meta = {}
    for d in ("scenarios", "scenarios_heldout"):
        for x in sc.load_dir(os.path.join(HERE, d)):
            meta[x.id] = (x.app, x.window_title)
    out = []
    for split, (a, b) in SETS.items():
        first, second = load(a), load(b)
        for row in combine(first, second):
            out.append({
                "id": row["id"], "split": split, "category": row["category"], "gold": row["gold"], "pred": row["pred"],
                "stage": row["stage"], "refused": bool(first[row["id"]].get("error") or second[row["id"]].get("error")),
                "sensitive": row["stage"] == "sensitive", "tags": row.get("tags", []),
                "app": meta[row["id"]][0], "title": meta[row["id"]][1],
            })
    path = os.path.join(R, "verdicts_two_judge.json")
    json.dump(out, open(path, "w"), indent=1)
    flagged_wrong = [r["id"] for r in out if r["pred"] == "off_task" and r["gold"] != "off_task"]
    print("wrote %d verdicts to %s" % (len(out), path))
    print("pred off_task but gold not off_task:", flagged_wrong)
    print("gold counts:", {g: sum(1 for r in out if r["gold"] == g) for g in ("on_task", "unsure", "off_task")})
    print("stages:", {s: sum(1 for r in out if r["stage"] == s) for s in ("sensitive", "rule", "model")})
    return 0


if __name__ == "__main__":
    sys.exit(main())
