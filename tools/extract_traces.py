#!/usr/bin/env python3
"""Extract the golden traces from docs/BRAIN-SPEC.md into core/traces/<name>.json.

  python3 tools/extract_traces.py          # write
  python3 tools/extract_traces.py --check  # exit 1 if the files differ from the spec

core/traces is what every brain implementation (Swift now, Rust or C# later) is run against.
"""
from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "docs", "BRAIN-SPEC.md")
OUT = os.path.join(ROOT, "core", "traces")


def main() -> int:
    text = open(SPEC).read()
    blocks = re.findall(r"```json\n(\{\"trace\".*?)\n```", text, re.S)
    traces = {}
    for b in blocks:
        t = json.loads(b)
        traces[t["trace"]] = b + "\n"
    if "--check" in sys.argv:
        bad = [n for n, b in traces.items() if not os.path.exists(os.path.join(OUT, n + ".json")) or open(os.path.join(OUT, n + ".json")).read() != b]
        print("stale:", bad or "none")
        return 1 if bad else 0
    os.makedirs(OUT, exist_ok=True)
    for n, b in traces.items():
        open(os.path.join(OUT, n + ".json"), "w").write(b)
    print("wrote %d traces to %s" % (len(traces), OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
