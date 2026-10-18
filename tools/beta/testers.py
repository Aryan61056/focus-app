#!/usr/bin/env python3
"""Who is testing, on what Mac, and which beta they last got. A CSV on this Mac only (beta/testers.csv, gitignored: it holds people's
names and how to reach them). It sends nothing; `invite` prints the text to paste into your own message.

  tools/beta/testers.py add NAME [--contact C] [--mac "M1 Pro, macOS 27"]
  tools/beta/testers.py list
  tools/beta/testers.py sent NAME BUILD          e.g. sent Sam 0.1.0-beta.3
  tools/beta/testers.py invite [BUILD]           prints beta/releases/BUILD/invite.txt (the newest when left out)
  tools/beta/testers.py drop NAME
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
ROSTER = ROOT / "beta" / "testers.csv"
RELEASES = ROOT / "beta" / "releases"
FIELDS = ["name", "contact", "mac", "joined", "last_build", "sent_on"]


def read(path: pathlib.Path = ROSTER) -> list:
    if not path.exists():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def write(rows: list, path: pathlib.Path = ROSTER) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    with tmp.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows({k: r.get(k, "") for k in FIELDS} for r in rows)
    tmp.replace(path)
    path.chmod(0o600)


def find(rows: list, name: str) -> dict:
    hits = [r for r in rows if r["name"].lower() == name.lower()]
    if not hits:
        raise SystemExit(f"no tester called {name!r}")
    return hits[0]


def newest_release() -> str | None:
    if not RELEASES.exists():
        return None
    def key(p):
        try:
            return int(p.name.rsplit(".", 1)[1])
        except (IndexError, ValueError):
            return -1
    rs = sorted((p for p in RELEASES.iterdir() if p.is_dir()), key=key)
    return rs[-1].name if rs else None


def main(argv=None, path: pathlib.Path = ROSTER) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    a_ = sub.add_parser("add"); a_.add_argument("name"); a_.add_argument("--contact", default=""); a_.add_argument("--mac", default="")
    sub.add_parser("list")
    s_ = sub.add_parser("sent"); s_.add_argument("name"); s_.add_argument("build")
    i_ = sub.add_parser("invite"); i_.add_argument("build", nargs="?")
    d_ = sub.add_parser("drop"); d_.add_argument("name")
    a = ap.parse_args(argv)
    rows = read(path)
    if a.cmd == "add":
        if any(r["name"].lower() == a.name.lower() for r in rows):
            raise SystemExit(f"{a.name} is already on the list")
        rows.append({"name": a.name, "contact": a.contact, "mac": a.mac, "joined": dt.date.today().isoformat(), "last_build": "", "sent_on": ""})
        write(rows, path); print(f"added {a.name} ({len(rows)} testers)")
    elif a.cmd == "list":
        if not rows:
            print("no testers yet"); return 0
        for r in rows:
            print(f"{r['name']:<18} {r['mac'] or '-':<22} {r['last_build'] or 'nothing sent':<18} {r['sent_on']}")
    elif a.cmd == "sent":
        r = find(rows, a.name); r["last_build"] = a.build; r["sent_on"] = dt.date.today().isoformat()
        write(rows, path); print(f"{r['name']} has {a.build}")
    elif a.cmd == "invite":
        b = a.build or newest_release()
        f = RELEASES / (b or "") / "invite.txt"
        if not b or not f.exists():
            raise SystemExit("no release yet: run tools/beta/release.sh")
        print(f.read_text(), end="")
    elif a.cmd == "drop":
        r = find(rows, a.name); rows.remove(r); write(rows, path); print(f"removed {r['name']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
