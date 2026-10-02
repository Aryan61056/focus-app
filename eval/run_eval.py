#!/usr/bin/env python3
"""Run the S1 accuracy eval.

  python3 eval/run_eval.py --validate
  python3 eval/run_eval.py --backend oracle
  python3 eval/run_eval.py --backend fm_swift --order reason-first --text-mode full

Stdlib only; works on the system Python 3.9.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from focus_eval import backends, ocr, pipeline, report, scenarios  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scenarios", default=os.path.join(HERE, "scenarios"))
    ap.add_argument("--validate", action="store_true", help="validate scenario files and exit")
    ap.add_argument("--backend", default="oracle", choices=["oracle", "always_unsure", "lexical", "fm_swift", "mlx_text", "mlx_vlm"])
    ap.add_argument("--order", default="reason-first", choices=["reason-first", "label-first", "relation", "relation-reasoned"])
    ap.add_argument("--text-mode", default="full", choices=["full", "titles", "ocr", "pixels"],
                    help="titles: app, title, url and path only; ocr: window text replaced by OCR of a synthetic screenshot; pixels: vision model reads the screenshot")
    ap.add_argument("--no-rules", action="store_true", help="skip stage 0/1 so every scenario reaches the model")
    ap.add_argument("--only", help="comma-separated scenario ids")
    ap.add_argument("--category", help="comma-separated categories")
    ap.add_argument("--out", default=os.path.join(HERE, "results"))
    ap.add_argument("--tag", default="", help="suffix for the result file name")
    args = ap.parse_args()

    try:
        items = scenarios.load_dir(args.scenarios)
    except scenarios.ScenarioError as e:
        print("scenario problems:\n%s" % e, file=sys.stderr)
        return 1
    if args.validate:
        from collections import Counter
        print("ok: %d scenarios" % len(items))
        print("labels:", dict(Counter(s.label for s in items)))
        print("difficulty:", dict(Counter(s.difficulty for s in items)))
        print("categories:", dict(Counter(s.category for s in items)))
        return 0
    if args.only:
        keep = set(args.only.split(","))
        items = [s for s in items if s.id in keep]
    if args.category:
        keep = set(args.category.split(","))
        items = [s for s in items if s.category in keep]

    ocr_map = ocr.ocr_texts(items) if args.text_mode in ("ocr", "pixels") else {}  # also renders the PNGs
    backend = backends.make(args.backend, args.order)
    label = "%s | text=%s | rules=%s" % (backend.name, args.text_mode, "off" if args.no_rules else "on")
    backend.start()
    t0 = time.time()
    try:
        def tick(i, n, s):
            if sys.stderr.isatty():
                sys.stderr.write("\r%d/%d %s   " % (i + 1, n, s.id))
        results = pipeline.run(items, backend, use_rules=not args.no_rules,
                               text_mode=args.text_mode, text_for=lambda sc: ocr_map.get(sc.id, ""), progress=tick)
    finally:
        backend.close()
    elapsed = time.time() - t0
    meta = {"label": label, "text_mode": args.text_mode, "use_rules": not args.no_rules,
            "backend": backend.name, "elapsed_s": round(elapsed, 1),
            "run_at": time.strftime("%Y-%m-%dT%H:%M:%S")}
    md = report.render(results, meta)
    os.makedirs(args.out, exist_ok=True)
    stem = "%s_%s_%s%s" % (backend.name.replace(":", "-"), args.text_mode,
                           "norules" if args.no_rules else "rules", ("_" + args.tag) if args.tag else "")
    with open(os.path.join(args.out, stem + ".json"), "w") as fh:
        json.dump({"meta": meta, "results": results}, fh, indent=1, ensure_ascii=False)
    with open(os.path.join(args.out, stem + ".md"), "w") as fh:
        fh.write(md)
    print(md)
    print("\n(saved %s.{json,md} in %s; %.1fs)" % (stem, args.out, elapsed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
