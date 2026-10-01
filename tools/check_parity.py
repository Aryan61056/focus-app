#!/usr/bin/env python3
"""Check the Swift port (mac/) against the Python eval harness on every scenario.

  python3 tools/check_parity.py

Compares (1) the exact prompt text and (2) the stage-0/1 decision (sensitive, rule hit, or goes to the model).
Exits 1 on any difference. Needs `swift build` to work in mac/.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "eval"))
from focus_eval import prompts, rules, scenarios  # noqa: E402


def swift(*args):
    env = dict(os.environ, DEVELOPER_DIR=subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip())
    env.pop("SDKROOT", None)
    r = subprocess.run(["swift", "run", "-q", "focus-judge", *args], cwd=os.path.join(ROOT, "mac"), env=env, capture_output=True, text=True)
    if r.returncode:
        sys.exit("swift failed: " + r.stderr[-800:])
    return r.stdout


def main() -> int:
    bad = 0
    for name in ("scenarios", "scenarios_heldout"):
        d = os.path.join(ROOT, "eval", name)
        items = scenarios.load_dir(d)
        dump = {}
        for line in swift("--dump-prompts", d).splitlines():
            sid, js = line.split("\t", 1)
            dump[sid] = json.loads('"' + js + '"') if not js.startswith('"') else json.loads(js)
        out = os.path.join(ROOT, "mac", ".build", "parity_%s.json" % name)
        swift("--run", d, "--stub", "--out", out)
        stage = {r["id"]: r for r in json.load(open(out))["results"]}
        for s in items:
            py_prompt = prompts.build_prompt(s)
            if dump.get(s.id) != py_prompt:
                bad += 1
                print("PROMPT DIFF", s.id)
            if rules.is_sensitive(s):
                py = ("sensitive", "unsure")
            elif rules.stage1(s):
                py = ("rule", rules.stage1(s)[0])
            else:
                py = ("model", "unsure")  # stub judge answers unsure
            sw = (stage[s.id]["stage"], stage[s.id]["pred"])
            if py != sw:
                bad += 1
                print("STAGE DIFF", s.id, "python", py, "swift", sw)
        print("%s: %d scenarios checked" % (name, len(items)))
    print("differences:", bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
