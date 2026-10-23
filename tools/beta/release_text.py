#!/usr/bin/env python3
"""The words around a beta build: its manifest (release.json), the invite to paste into a message, and the GitHub release text.
Used by tools/beta/release.sh and tools/beta/publish.sh. Reads and writes local files only.

  release_text.py --origin-repo ROOT           the origin remote as https://github.com/<owner>/<repo>, or nothing
  release_text.py --manifest OUT --name N ...  writes release.json (see release.sh for the arguments)
  release_text.py --invite release.json        the invite text
  release_text.py --github release.json        the GitHub release body (Markdown)
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import subprocess
import sys

REPO_RE = re.compile(r"^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
ISSUE_FORMS = [("Something broke", "beta-bug.yml"), ("Wrong call", "beta-wrong-call.yml"), ("Idea", "beta-idea.yml")]


def origin_repo(remote: str) -> str:
    """https://github.com/<owner>/<repo> for a GitHub remote in either form, else an empty string."""
    m = re.match(r"^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$", remote.strip())
    return f"https://github.com/{m.group(1)}/{m.group(2)}" if m else ""


def items(path: str) -> list:
    """One item per line, '- ' and '* ' bullets dropped, headings and blank lines left out (the app reads them the same way)."""
    p = pathlib.Path(path)
    if not p.exists():
        return []
    out = []
    for line in p.read_text().splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        out.append(s[2:] if s[:2] in ("- ", "* ") else s)
    return out


def label(m: dict) -> str:
    return f"{m['version']} beta {m['build']}"


def day(iso: str) -> str:
    d = dt.date.fromisoformat(iso)
    return f"{d.strftime('%B')} {d.day}, {d.year}"


def invite(m: dict) -> str:
    repo = m.get("repo")
    open_step = (" macOS will say it cannot check the app: choose Done, then System Settings, Privacy & Security, Open Anyway. Once only."
                 if m.get("signing") == "ad-hoc" else "")
    lines = [
        f"Hushd {label(m)} is ready to try.",
        "",
        f"1. Open {m['dmg']} and drag Hushd onto Applications." if not repo else
        f"1. Download {m['dmg']} from {repo}/releases/tag/{m['tag']}, open it and drag Hushd onto Applications.",
        f"2. Open it from Applications.{open_step}",
        "3. Work as you normally would for a week. Hushd needs Apple silicon and Apple Intelligence turned on.",
        "",
        "When something breaks, feels wrong or gives you an idea: click your name at the bottom left of the Hushd window, then Send feedback.",
        "You see the whole report before you save it. Hushd never sends a report by itself, and reports never hold your task names, window",
        "titles, addresses or anything from your screen.",
    ]
    if repo:
        lines.append(f"Post it at {repo}/issues (Hushd opens the form for you), or send the file back to me.")
    lines += ["", f"This build stops being current on {m['expires']}. It keeps working after that.", f"Checksum (SHA-256): {m['sha256']}"]
    return "\n".join(lines) + "\n"


def github_body(m: dict) -> str:
    repo = m.get("repo") or ""
    out = [f"A test build of Hushd for Mac. Current until **{day(m['expires'])}**; it keeps working after that.", ""]
    out += ["### Install", "", f"1. Download **{m['dmg']}** below.", "2. Open it and drag **Hushd** onto **Applications**."]
    if m.get("signing") == "ad-hoc":
        out += ["3. Open Hushd. macOS says it cannot check the app, because this build has no Apple developer signature yet. "
                "Choose **Done**, then **System Settings › Privacy & Security › Open Anyway**. Once per build."]
    else:
        out += ["3. Open Hushd from Applications."]
    out += ["", "Needs a Mac with Apple silicon and Apple Intelligence turned on. A newer beta installs over this one; your sessions and settings stay.", ""]
    if m.get("notes"):
        out += ["### New in this build", ""] + [f"- {n}" for n in m["notes"]] + [""]
    if m.get("known"):
        out += ["### Known issues", "", "Already on the list, no report needed:", ""] + [f"- {k}" for k in m["known"]] + [""]
    out += ["### Send feedback", "",
            "In Hushd: your name at the bottom left, then **Send feedback**. You see the whole report before it is saved; "
            "**Post on GitHub** opens the form, and you drag the file in."]
    if repo:
        out += ["", "Or open a form here: " + " · ".join(f"[{t}]({repo}/issues/new?template={f})" for t, f in ISSUE_FORMS) + "."]
    out += ["", "Issues are public. Reports never hold task or project names, window titles, addresses, screen words or pictures. "
            "Hushd never sends a report by itself.", "",
            f"<sub>Build {m['build']} · {m['buildID']} · SHA-256 `{m['sha256']}` · {m['signing']} signed</sub>"]
    return "\n".join(out) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--origin-repo", metavar="ROOT")
    ap.add_argument("--invite", metavar="MANIFEST")
    ap.add_argument("--github", metavar="MANIFEST")
    ap.add_argument("--manifest", metavar="OUT")
    for k in ("name", "version", "build", "build-id", "expires", "sha", "signing", "commit", "notes", "known", "repo"):
        ap.add_argument(f"--{k}", default="")
    ap.add_argument("--email", action="store_true")
    a = ap.parse_args(argv)
    if a.origin_repo is not None:
        try:
            url = subprocess.run(["git", "-C", a.origin_repo, "remote", "get-url", "origin"], capture_output=True, text=True).stdout
        except OSError:
            url = ""
        print(origin_repo(url))
        return 0
    if a.manifest:
        if a.repo and not REPO_RE.match(a.repo):
            raise SystemExit("--repo must be https://github.com/<owner>/<repo>")
        m = {"name": a.name, "version": a.version, "build": int(a.build), "buildID": a.build_id, "made": dt.date.today().isoformat(),
             "expires": a.expires, "sha256": a.sha, "signing": a.signing, "feedbackEmail": a.email, "commit": a.commit,
             "repo": a.repo or None, "tag": f"v{a.name}", "dmg": f"Focus-{a.name}.dmg", "notes": items(a.notes), "known": items(a.known)}
        pathlib.Path(a.manifest).write_text(json.dumps(m, indent=2) + "\n")
        return 0
    if a.invite:
        sys.stdout.write(invite(json.loads(pathlib.Path(a.invite).read_text())))
        return 0
    if a.github:
        sys.stdout.write(github_body(json.loads(pathlib.Path(a.github).read_text())))
        return 0
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
