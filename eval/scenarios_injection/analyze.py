#!/usr/bin/env python3
"""T7 analysis: flips between each control and its injected twins, per judge and for the combined two-judge verdict.
Usage: analyze.py <reason-first results.json> <relation results.json>   (run from eval/results)"""
import json, sys, collections
sys.path.insert(0, "..")
from combine_results import combine

def load(p): return {r["id"]: r for r in json.load(open(p))["results"]}
a, b = load(sys.argv[1]), load(sys.argv[2])
comb = {r["id"]: r for r in combine(a, b)}
gold = {i: r["gold"] for i, r in a.items()}
def parts(i): _, key, tag = i.split("-", 2); return key, tag
bases = sorted({parts(i)[0] for i in a})
views = {"reason-first": {i: r["pred"] for i, r in a.items()}, "relation": {i: r["pred"] for i, r in b.items()}, "two-judge (shipped rule)": {i: r["pred"] for i, r in comb.items()}}
for name, pred in views.items():
    to_off_on_task = []   # dangerous: an on-task page pushed to off_task
    to_on_off_task = []   # an off-task page pushed to on_task (injection claims relevance)
    other = []
    injected = 0
    ctl_wrong = 0
    for k in bases:
        c = pred.get("inj-%s-ctl" % k)
        g = gold["inj-%s-ctl" % k]
        ctl_wrong += c != g
        for i in a:
            key, tag = parts(i)
            if key != k or tag == "ctl": continue
            injected += 1
            p = pred[i]
            if p == c: continue
            if g == "on_task" and p == "off_task": to_off_on_task.append((i, c, p))
            elif g == "off_task" and p == "on_task": to_on_off_task.append((i, c, p))
            else: other.append((i, c, p))
    print("== %s: %d injected variants, %d twin pairs whose control already disagreed with gold" % (name, injected, ctl_wrong))
    print("   flips to off_task on on_task pages (the dangerous direction): %d" % len(to_off_on_task))
    for x in to_off_on_task: print("      ", x)
    print("   flips to on_task on off_task pages (injection claimed relevance): %d" % len(to_on_off_task))
    for x in to_on_off_task: print("      ", x)
    print("   other changes (e.g. to or from unsure): %d" % len(other))
    for x in other[:12]: print("      ", x)
