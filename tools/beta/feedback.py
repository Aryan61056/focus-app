#!/usr/bin/env python3
"""Beta feedback inbox: check, file, triage and summarize the reports testers send (schema focus-feedback/1, see docs/BETA.md).

Reports arrive as files the tester saved in Focus and either attached to a GitHub issue or sent however they chose. The tool reads the
files you give it, keeps them under beta/inbox/ (gitignored: reports hold what testers typed) and writes a summary you open locally.
Only `pull` reaches the network: it lists the repository's issues labelled `beta` with the GitHub CLI and downloads the .json files
attached to them, nothing else, then files them like `ingest` (each one validated, the issue number recorded).

  tools/beta/feedback.py check FILE...           validate only; exit 1 if any is refused
  tools/beta/feedback.py ingest PATH...          files or folders; valid reports are filed, refused ones are listed with reasons
  tools/beta/feedback.py pull [--repo OWNER/REPO] reports attached to `beta` issues on GitHub (default: the origin remote's project)
  tools/beta/feedback.py list [--status S] [--kind K] [--build B]
  tools/beta/feedback.py show ID                 an ID prefix is enough
  tools/beta/feedback.py triage ID STATUS [--note TEXT] [--issue REF]
  tools/beta/feedback.py report                  writes beta/inbox/REPORT.md and beta/inbox/report.html

A report is refused when it does not match the schema or carries something it never should: a file path (a user name lives in
/Users/<name>), a long string outside the tester's own message, an unknown event kind. The app cannot produce those; a refusal means
the file was edited or came from somewhere else, so look at it before trusting it.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import html
import json
import pathlib
import re
import statistics
import sys
from collections import Counter, defaultdict

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
INBOX = ROOT / "beta" / "inbox"

SCHEMA = "focus-feedback/1"
KINDS = {"bug", "wrongCall", "idea", "other"}
CHANNELS = {"dev", "beta", "release"}
EVENT_KINDS = {
    "launch", "quit", "uncleanExit", "sessionStart", "sessionEnd", "warning", "pauseScreen", "checkIn", "backToTask",
    "judgeRefusal", "judgeUnavailable", "saveFailed", "hang", "feedbackSaved", "pulseAnswered",
}
STATUSES = ["new", "triaged", "fixing", "fixed", "wontfix", "duplicate"]
TOP_KEYS = {"schema", "id", "created", "kind", "message", "contact", "app", "system", "settings", "usage", "events", "pulses", "crash", "calls"}
APP_KEYS = {"version", "build", "buildID", "channel"}
SYSTEM_KEYS = {"macOS", "model", "memoryGB", "appleSilicon", "lowPower", "judge", "windowAccess", "screenRecording"}
USAGE_KEYS = {"sessions", "sessionsLast14Days", "activeMinutesLast14Days", "onTaskMinutesLast14Days", "drifts", "nudges", "refusals",
              "reads", "reviewAnswered", "reviewAgreed", "projects", "projectsDescribed", "daysUsed"}
READ_KEYS = {"model", "rule", "onTask", "unsure", "offTask", "skipped"}
CRASH_KEYS = {"when", "appVersion", "osVersion", "exception", "signal", "termination", "frames"}
CALLS = {"on", "unsure", "off"}
CALL_BY = {"model", "rule", "words", "refused", "private", "skipped"}
MESSAGE_LIMIT = 4000
SHORT = 64           # any string the app writes itself is shorter than this, except crash frames
FRAME_LIMIT = 160
PATH_RE = re.compile(r"/(Users|home|private|var/folders)/", re.I)
# Things a tester may have typed by accident. A warning, not a refusal: it is their own message.
SENSITIVE_RE = [
    (re.compile(r"\b(password|passcode|passwd)\s*[:=]", re.I), "looks like a password"),
    (re.compile(r"\b\d{4}[ -]?\d{4}[ -]?\d{4}[ -]?\d{4}\b"), "looks like a card number"),
    (re.compile(r"\b(sk|pk|ghp|xox[bp])[-_][A-Za-z0-9]{12,}"), "looks like an API key"),
]


class Refused(Exception):
    pass


# ---------------------------------------------------------------- validation

def _want(cond: bool, why: str) -> None:
    if not cond:
        raise Refused(why)


def _date(v, where: str) -> dt.datetime:
    _want(isinstance(v, str), f"{where} is not a date")
    try:
        return dt.datetime.fromisoformat(v.replace("Z", "+00:00"))
    except ValueError:
        raise Refused(f"{where} is not an ISO date: {v[:30]!r}")


def _short(v, where: str, limit: int = SHORT) -> None:
    _want(isinstance(v, str), f"{where} is not text")
    _want(len(v) <= limit, f"{where} is longer than the app ever writes ({len(v)} > {limit})")
    _want(not PATH_RE.search(v), f"{where} holds a file path")


def _int(v, where: str) -> None:
    _want(isinstance(v, int) and not isinstance(v, bool) and v >= 0, f"{where} is not a count")


def _keys(d, allowed: set, where: str) -> None:
    _want(isinstance(d, dict), f"{where} is not an object")
    extra = set(d) - allowed
    _want(not extra, f"{where} has keys the app never writes: {sorted(extra)}")


def validate(r) -> list:
    """Raises Refused for a report the app could not have written. Returns warnings about the tester's own words."""
    _keys(r, TOP_KEYS, "report")
    _want(r.get("schema") == SCHEMA, f"schema is {r.get('schema')!r}, expected {SCHEMA}")
    _want(isinstance(r.get("id"), str) and re.fullmatch(r"[0-9a-f-]{36}", r["id"]) is not None, "id is not a UUID")
    _date(r.get("created"), "created")
    _want(r.get("kind") in KINDS, f"kind {r.get('kind')!r} is unknown")
    msg = r.get("message")
    _want(isinstance(msg, str) and msg.strip() != "", "message is empty")
    _want(len(msg) <= MESSAGE_LIMIT, "message is longer than the app allows")
    if "contact" in r:
        _short(r["contact"], "contact", 200)

    _keys(r.get("app"), APP_KEYS, "app")
    for k in ("version", "build", "channel"):
        _short(r["app"].get(k), f"app.{k}")
    _want(r["app"]["channel"] in CHANNELS, "app.channel is unknown")
    if "buildID" in r["app"]:
        _short(r["app"]["buildID"], "app.buildID")

    if "system" in r:
        s = r["system"]
        _keys(s, SYSTEM_KEYS, "system")
        for k in ("macOS", "model", "judge", "windowAccess", "screenRecording"):
            _short(s.get(k), f"system.{k}")
        _int(s.get("memoryGB"), "system.memoryGB")
        for k in ("appleSilicon", "lowPower"):
            _want(isinstance(s.get(k), bool), f"system.{k} is not true or false")

    if "settings" in r:
        _want(isinstance(r["settings"], dict) and len(r["settings"]) <= 80, "settings is not a small object")
        for k, v in r["settings"].items():
            _short(k, "a settings name", 40)
            _short(v, f"settings.{k}", 16)

    if "usage" in r:
        u = r["usage"]
        _keys(u, USAGE_KEYS, "usage")
        for k in USAGE_KEYS - {"reads"}:
            _int(u.get(k), f"usage.{k}")
        _keys(u.get("reads"), READ_KEYS, "usage.reads")
        for k, v in u["reads"].items():
            _int(v, f"usage.reads.{k}")

    if "events" in r:
        _want(isinstance(r["events"], list) and len(r["events"]) <= 600, "events is not a short list")
        for i, e in enumerate(r["events"]):
            _keys(e, {"at", "kind", "value"}, f"events[{i}]")
            _date(e.get("at"), f"events[{i}].at")
            _want(e.get("kind") in EVENT_KINDS, f"events[{i}].kind {e.get('kind')!r} is unknown")
            if "value" in e:
                _want(isinstance(e["value"], (int, float)) and not isinstance(e["value"], bool), f"events[{i}].value is not a number")

    if "pulses" in r:
        _want(isinstance(r["pulses"], list) and len(r["pulses"]) <= 60, "pulses is not a short list")
        for i, p in enumerate(r["pulses"]):
            _keys(p, {"at", "score", "note"}, f"pulses[{i}]")
            _date(p.get("at"), f"pulses[{i}].at")
            _want(p.get("score") in (1, 2, 3, 4, 5), f"pulses[{i}].score is not 1 to 5")
            if "note" in p:
                _want(isinstance(p["note"], str) and len(p["note"]) <= 500, f"pulses[{i}].note is too long")

    if "crash" in r:
        c = r["crash"]
        _keys(c, CRASH_KEYS, "crash")
        for k in ("appVersion", "osVersion", "exception", "signal", "termination"):
            if k in c:
                _short(c[k], f"crash.{k}", FRAME_LIMIT)
        if "when" in c:
            _date(c["when"], "crash.when")
        _want(isinstance(c.get("frames"), list) and len(c["frames"]) <= 24, "crash.frames is not a short list")
        for i, f in enumerate(c["frames"]):
            _short(f, f"crash.frames[{i}]", FRAME_LIMIT)

    if "calls" in r:
        _want(isinstance(r["calls"], list) and len(r["calls"]) <= 12, "calls is not a short list")
        for i, c in enumerate(r["calls"]):
            _keys(c, {"at", "call", "by"}, f"calls[{i}]")
            _date(c.get("at"), f"calls[{i}].at")
            _want(c.get("call") in CALLS, f"calls[{i}].call {c.get('call')!r} is unknown")
            _want(c.get("by") in CALL_BY, f"calls[{i}].by {c.get('by')!r} is unknown")

    warnings = []
    texts = [msg] + [p.get("note", "") for p in r.get("pulses", [])] + [r.get("contact", "")]
    for t in texts:
        for rx, why in SENSITIVE_RE:
            if rx.search(t):
                warnings.append(why)
    return sorted(set(warnings))


def load(path: pathlib.Path) -> dict:
    try:
        raw = path.read_bytes()
    except OSError as e:
        raise Refused(f"cannot read: {e.strerror}")
    _want(len(raw) <= 512 * 1024, "file is larger than any report")
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise Refused("not JSON")


# ---------------------------------------------------------------- inbox

def _triage_path(inbox: pathlib.Path) -> pathlib.Path:
    return inbox / "triage.json"


def read_triage(inbox: pathlib.Path) -> dict:
    p = _triage_path(inbox)
    return json.loads(p.read_text()) if p.exists() else {}


def write_triage(inbox: pathlib.Path, t: dict) -> None:
    inbox.mkdir(parents=True, exist_ok=True)
    tmp = _triage_path(inbox).with_suffix(".tmp")
    tmp.write_text(json.dumps(t, indent=2, sort_keys=True))
    tmp.replace(_triage_path(inbox))


def reports(inbox: pathlib.Path) -> list:
    d = inbox / "reports"
    return [json.loads(p.read_text()) for p in sorted(d.glob("*.json"))] if d.exists() else []


def candidates(paths: list) -> list:
    out = []
    for p in map(pathlib.Path, paths):
        if p.is_dir():
            out += sorted(x for x in p.rglob("*.json") if x.is_file())
        else:
            out.append(p)
    return out


def ingest(paths: list, inbox: pathlib.Path = INBOX, today: str | None = None, issues: dict | None = None) -> tuple:
    """Files valid reports. `issues` maps a file path to where it came from on GitHub ({"issue": "#12", "source": url})."""
    issues = issues or {}
    triage = read_triage(inbox)
    filed, dupes, refused = [], [], []
    (inbox / "reports").mkdir(parents=True, exist_ok=True)
    for p in candidates(paths):
        try:
            r = load(p)
            warnings = validate(r)
        except Refused as e:
            refused.append((str(p), str(e)))
            continue
        rid = r["id"]
        if rid in triage:
            dupes.append(rid)
            continue
        (inbox / "reports" / f"{rid}.json").write_text(json.dumps(r, indent=2, sort_keys=True))
        triage[rid] = {"status": "new", "received": today or dt.date.today().isoformat(),
                       "sha256": hashlib.sha256(p.read_bytes()).hexdigest(), "warnings": warnings, "notes": [],
                       "issue": issues.get(str(p), {}).get("issue")}
        if issues.get(str(p), {}).get("source"):
            triage[rid]["source"] = issues[str(p)]["source"]
        filed.append((rid, warnings))
    write_triage(inbox, triage)
    return filed, dupes, refused


# ---------------------------------------------------------------- GitHub

# Files people attach to issues and comments. Both forms GitHub has used; only .json, only on github.com.
ATTACHMENT_RE = re.compile(r"https://github\.com/(?:user-attachments/files|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/files)/\d+/[A-Za-z0-9_.%-]+\.json")


def attachments(issue: dict) -> list:
    """The .json attachments in an issue's body and comments, in order, each once."""
    texts = [issue.get("body") or ""] + [(c or {}).get("body") or "" for c in issue.get("comments") or []]
    seen, out = set(), []
    for t in texts:
        for u in ATTACHMENT_RE.findall(t):
            if u not in seen:
                seen.add(u)
                out.append(u)
    return out


def gh_issues(repo: str) -> list:
    import subprocess
    r = subprocess.run(["gh", "issue", "list", "--repo", repo, "--label", "beta", "--state", "all", "--limit", "500",
                        "--json", "number,title,body,comments,url"], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"gh could not list issues: {r.stderr.strip()}")
    return json.loads(r.stdout or "[]")


def download(url: str, limit: int = 512 * 1024) -> bytes:
    """One attachment, at most `limit` bytes. Only github.com addresses are passed in; GitHub redirects them to its file host."""
    import urllib.request
    with urllib.request.urlopen(urllib.request.Request(url, headers={"Accept": "application/json"}), timeout=20) as resp:
        data = resp.read(limit + 1)
    if len(data) > limit:
        raise Refused("attachment is larger than any report")
    return data


def pull(repo: str, inbox: pathlib.Path = INBOX, fetch_issues=gh_issues, fetch=download, today: str | None = None) -> tuple:
    """Downloads report files attached to `beta` issues into a fresh folder and files them. Returns ingest's result plus failures."""
    import tempfile
    t = read_triage(inbox)
    known = {v.get("source") for v in t.values()}
    work = pathlib.Path(tempfile.mkdtemp(prefix="focus-pull-"))
    paths, issues, failed = [], {}, []
    for issue in fetch_issues(repo):
        for i, url in enumerate(attachments(issue)):
            if url in known:
                continue
            dest = work / f"issue-{issue['number']}-{i}.json"
            try:
                dest.write_bytes(fetch(url))
            except (Refused, OSError, ValueError) as e:
                failed.append((url, str(e)))
                continue
            paths.append(str(dest))
            issues[str(dest)] = {"issue": f"#{issue['number']}", "source": url}
    filed, dupes, refused = ingest(paths, inbox, today=today, issues=issues)
    return filed, dupes, refused, failed


def origin_repo() -> str:
    import subprocess
    url = subprocess.run(["git", "-C", str(ROOT), "remote", "get-url", "origin"], capture_output=True, text=True).stdout.strip()
    m = re.match(r"^(?:https://github\.com/|git@github\.com:)([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?$", url)
    if not m:
        raise SystemExit("the origin remote is not a GitHub project; pass --repo OWNER/REPO")
    return f"{m.group(1)}/{m.group(2)}"


def find(prefix: str, triage: dict) -> str:
    hits = [k for k in triage if k.startswith(prefix.lower())]
    if len(hits) != 1:
        raise SystemExit(f"{'no' if not hits else 'more than one'} report matches {prefix!r}")
    return hits[0]


def set_status(inbox: pathlib.Path, prefix: str, status: str, note: str | None = None, issue: str | None = None) -> str:
    if status not in STATUSES:
        raise SystemExit(f"status must be one of {', '.join(STATUSES)}")
    t = read_triage(inbox)
    rid = find(prefix, t)
    t[rid]["status"] = status
    if note:
        t[rid]["notes"].append({"on": dt.date.today().isoformat(), "text": note})
    if issue:
        t[rid]["issue"] = issue
    write_triage(inbox, t)
    return rid


# ---------------------------------------------------------------- summary

def crash_signature(c: dict) -> str:
    """What went wrong and the first frame inside Focus itself, so the same crash from two testers groups together."""
    ours = next((f for f in c.get("frames", []) if f.startswith(("focus-app ", "FocusUI", "FocusSense", "FocusBrain", "FocusJudge"))), None)
    head = " ".join(x for x in (c.get("exception"), c.get("signal")) if x) or c.get("termination") or "unknown"
    return f"{head} at {ours or (c.get('frames') or ['?'])[0]}"


def week(d: str) -> str:
    x = dt.datetime.fromisoformat(d.replace("Z", "+00:00")).date()
    y, w, _ = x.isocalendar()
    return f"{y}-W{w:02d}"


def summarize(rs: list, triage: dict) -> dict:
    by_kind = Counter(r["kind"] for r in rs)
    by_build = Counter(f"{r['app']['version']} b{r['app']['build']}" for r in rs)
    by_status = Counter(triage.get(r["id"], {}).get("status", "new") for r in rs)
    macs = Counter(f"macOS {r['system']['macOS']} · {r['system']['model']} · {r['system']['memoryGB']} GB" for r in rs if "system" in r)
    judge = Counter(r["system"]["judge"] for r in rs if "system" in r)
    crashes = Counter(crash_signature(r["crash"]) for r in rs if "crash" in r)
    # For a wrong call, how Focus reached its newest call before the report: the model, a rule, or words shared with the task.
    wrong_by = Counter(r["calls"][0]["by"] for r in rs if r["kind"] == "wrongCall" and r.get("calls"))
    # Journals overlap between reports from one tester; count each event once by (time, kind).
    seen, events = set(), []
    for r in rs:
        for e in r.get("events", []):
            key = (e["at"], e["kind"])
            if key not in seen:
                seen.add(key)
                events.append(e)
    ev = Counter(e["kind"] for e in events)
    hang_secs = [e.get("value", 0) for e in events if e["kind"] == "hang"]
    back = [e.get("value", 0) for e in events if e["kind"] == "backToTask"]
    starts = ev["sessionStart"]
    pulses, pseen = defaultdict(list), set()
    for r in rs:
        for p in r.get("pulses", []):
            if p["at"] not in pseen:
                pseen.add(p["at"])
                pulses[week(p["at"])].append(p["score"])
    usage = [r["usage"] for r in rs if "usage" in r]
    agreed = sum(u["reviewAgreed"] for u in usage)
    answered = sum(u["reviewAnswered"] for u in usage)
    return {
        "reports": len(rs), "by_kind": by_kind, "by_build": by_build, "by_status": by_status, "macs": macs, "judge": judge,
        "crashes": crashes, "events": ev, "sessions": starts,
        "unclean_per_100": round(100 * ev["uncleanExit"] / ev["launch"], 1) if ev["launch"] else None,
        "hangs": len(hang_secs), "hang_median": round(statistics.median(hang_secs), 1) if hang_secs else None,
        "nudges_per_session": round((ev["warning"] + ev["pauseScreen"]) / starts, 2) if starts else None,
        "back_found": round(100 * sum(1 for b in back if b >= 1) / len(back)) if back else None,
        "refusals": ev["judgeRefusal"],
        "pulse_weeks": {w: (round(statistics.mean(v), 2), len(v)) for w, v in sorted(pulses.items())},
        "review": (agreed, answered),
        "wrong_call_share": round(100 * by_kind["wrongCall"] / len(rs)) if rs else None,
        "wrong_by": wrong_by,
    }


def _table(rows, head) -> str:
    out = ["| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
    out += ["| " + " | ".join(str(c) for c in row) + " |" for row in rows]
    return "\n".join(out)


def markdown(s: dict, rs: list, triage: dict, made: str) -> str:
    def opt(v, unit=""):
        return "n/a" if v is None else f"{v}{unit}"
    lines = [f"# Beta feedback", "", f"Made {made} from {s['reports']} report(s). Counts from testers' own logs; small samples, so treat",
             "every number as a hint, not a measurement (CLAUDE.md, eval conventions).", "",
             "## Health", "",
             _table([
                 ["Sessions in the logs", s["sessions"]],
                 ["Unclean exits per 100 launches", opt(s["unclean_per_100"])],
                 ["Slow moments (2 s or more)", f"{s['hangs']} (median {opt(s['hang_median'], ' s')})"],
                 ["Nudges per session", opt(s["nudges_per_session"])],
                 ["Back to task found the place", opt(s["back_found"], "%")],
                 ["Model refusals", s["refusals"]],
                 ["Review: Focus was right", f"{s['review'][0]} of {s['review'][1]}"],
                 ["Reports that are wrong calls", opt(s["wrong_call_share"], "%")],
             ], ["Measure", "Value"]), "",
             "## Weekly question (1 to 5)", ""]
    lines.append(_table([[w, m, n] for w, (m, n) in s["pulse_weeks"].items()], ["Week", "Mean", "Answers"]) if s["pulse_weeks"] else "No answers yet.")
    lines += ["", "## Wrong calls: how Focus decided", ""]
    lines.append(_table(s["wrong_by"].most_common(), ["Newest call by", "Reports"]) if s["wrong_by"] else "No wrong-call reports with calls yet.")
    lines += ["", "## Crashes", ""]
    lines.append(_table(s["crashes"].most_common(), ["Signature", "Reports"]) if s["crashes"] else "None reported.")
    lines += ["", "## Reports by kind, build and status", "",
              _table(sorted(s["by_kind"].items()), ["Kind", "Reports"]), "",
              _table(sorted(s["by_build"].items()), ["Build", "Reports"]), "",
              _table([[k, s["by_status"].get(k, 0)] for k in STATUSES], ["Status", "Reports"]), "",
              "## Macs", "", _table(s["macs"].most_common(), ["Mac", "Reports"]) if s["macs"] else "None.", "",
              "## Open", ""]
    open_rs = [r for r in sorted(rs, key=lambda r: r["created"]) if triage.get(r["id"], {}).get("status", "new") in ("new", "triaged", "fixing")]
    if not open_rs:
        lines.append("Nothing open.")
    for r in open_rs:
        t = triage.get(r["id"], {})
        first = r["message"].strip().splitlines()[0][:140]
        warn = f" ⚠ {', '.join(t.get('warnings', []))}" if t.get("warnings") else ""
        issue = f" · {t['issue']}" if t.get("issue") else ""
        lines.append(f"- `{r['id'][:8]}` {r['kind']} · b{r['app']['build']} · {t.get('status', 'new')}{issue}{warn}: {first}")
    return "\n".join(lines) + "\n"


def page(s: dict, rs: list, triage: dict, made: str) -> str:
    """One static page, no scripts or outside files, light and dark. Opened locally; never published."""
    esc = html.escape

    def bars(counter, total=None):
        total = total or max(counter.values() or [1])
        rows = []
        for k, v in counter.most_common():
            w = 100 * v / total if total else 0
            rows.append(f'<div class="bar"><span class="k">{esc(str(k))}</span><span class="t"><i style="width:{w:.0f}%"></i></span><span class="v">{v}</span></div>')
        return "".join(rows) or '<p class="muted">None yet.</p>'

    def tile(label, value):
        return f'<div class="tile"><div class="v">{esc(str(value))}</div><div class="l">{esc(label)}</div></div>'

    pulse = "".join(
        f'<div class="col" title="{esc(w)}: {m} from {n}"><i style="height:{m / 5 * 100:.0f}%"></i><span>{esc(w[-3:])}</span></div>'
        for w, (m, n) in s["pulse_weeks"].items()) or '<p class="muted">No answers yet.</p>'
    open_rows = "".join(
        f'<tr><td><code>{esc(r["id"][:8])}</code></td><td>{esc(r["kind"])}</td><td>b{esc(r["app"]["build"])}</td>'
        f'<td>{esc(triage.get(r["id"], {}).get("status", "new"))}</td><td>{esc(r["message"].strip()[:220])}</td></tr>'
        for r in sorted(rs, key=lambda r: r["created"], reverse=True)
        if triage.get(r["id"], {}).get("status", "new") in ("new", "triaged", "fixing"))
    def na(v, unit=""):
        return "n/a" if v is None else f"{v}{unit}"
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Beta feedback</title><style>
:root{{--bg:#f3f8f5;--card:#fff;--ink:#1a1b1b;--ink2:#56595a;--line:rgba(26,27,27,.11);--accent:#1b7548;--track:rgba(26,27,27,.12);--slip:#8f5200}}
@media (prefers-color-scheme:dark){{:root{{--bg:#0f1612;--card:#18211c;--ink:#edeeee;--ink2:#a9adae;--line:rgba(255,255,255,.1);--accent:#78d59d;--track:rgba(255,255,255,.14);--slip:#f0b060}}}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--ink);font:14px/1.45 -apple-system,system-ui,sans-serif}}
main{{max-width:1040px;margin:0 auto;padding:32px 16px 64px}}h1{{font-size:22px;margin:0 0 4px}}h2{{font-size:15px;margin:0 0 12px}}
.muted{{color:var(--ink2)}}section{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-top:16px}}
.tiles{{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-top:20px}}
.tile{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px 14px}}.tile .v{{font:600 22px ui-monospace,SFMono-Regular,monospace}}.tile .l{{color:var(--ink2);font-size:12px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px}}.grid section{{margin-top:0}}
.bar{{display:grid;grid-template-columns:minmax(0,1.6fr) 1fr 40px;gap:8px;align-items:center;margin:6px 0}}.bar .k{{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}}
.bar .t{{height:6px;background:var(--track);border-radius:3px;overflow:hidden}}.bar i{{display:block;height:100%;background:var(--accent)}}.bar .v{{text-align:right;font-family:ui-monospace,monospace}}
.cols{{display:flex;gap:8px;align-items:flex-end;height:120px}}.col{{flex:1;display:flex;flex-direction:column;justify-content:flex-end;align-items:center;height:100%;gap:4px}}
.col i{{display:block;width:100%;max-width:32px;background:var(--accent);border-radius:4px 4px 0 0}}.col span{{font-size:11px;color:var(--ink2)}}
table{{width:100%;border-collapse:collapse}}td,th{{text-align:left;padding:6px 8px;border-top:1px solid var(--line);vertical-align:top}}th{{color:var(--ink2);font-weight:500;border-top:0}}
code{{font-family:ui-monospace,monospace}}.wrap{{overflow-x:auto}}
</style></head><body><main>
<h1>Beta feedback</h1><p class="muted">{esc(made)} · {s['reports']} report(s). Small samples: every number is a hint.</p>
<div class="tiles">{tile('sessions in logs', s['sessions'])}{tile('unclean exits / 100 launches', na(s['unclean_per_100']))}{tile('slow moments', s['hangs'])}
{tile('nudges per session', na(s['nudges_per_session']))}{tile('back to task found it', na(s['back_found'], '%'))}{tile('Review agreed', f"{s['review'][0]}/{s['review'][1]}")}</div>
<section><h2>Weekly question</h2><div class="cols">{pulse}</div></section>
<div class="grid" style="margin-top:16px"><section><h2>Kinds</h2>{bars(s['by_kind'])}</section><section><h2>Builds</h2>{bars(s['by_build'])}</section>
<section><h2>Crashes</h2>{bars(s['crashes'])}</section><section><h2>Macs</h2>{bars(s['macs'])}</section>
<section><h2>Wrong calls: how Focus decided</h2>{bars(s['wrong_by'])}</section></div>
<section><h2>Open</h2><div class="wrap"><table><tr><th>ID</th><th>Kind</th><th>Build</th><th>Status</th><th>Message</th></tr>{open_rows or '<tr><td colspan="5" class="muted">Nothing open.</td></tr>'}</table></div></section>
</main></body></html>
"""


def write_report(inbox: pathlib.Path = INBOX, made: str | None = None) -> tuple:
    rs = reports(inbox)
    t = read_triage(inbox)
    made = made or dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    s = summarize(rs, t)
    inbox.mkdir(parents=True, exist_ok=True)
    md, pg = inbox / "REPORT.md", inbox / "report.html"
    md.write_text(markdown(s, rs, t, made))
    pg.write_text(page(s, rs, t, made))
    return md, pg


# ---------------------------------------------------------------- command line

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--inbox", default=str(INBOX), help=argparse.SUPPRESS)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check").add_argument("files", nargs="+")
    sub.add_parser("ingest").add_argument("paths", nargs="+")
    sub.add_parser("pull").add_argument("--repo")
    ls = sub.add_parser("list")
    ls.add_argument("--status"); ls.add_argument("--kind"); ls.add_argument("--build")
    sub.add_parser("show").add_argument("id")
    tr = sub.add_parser("triage")
    tr.add_argument("id"); tr.add_argument("status", choices=STATUSES); tr.add_argument("--note"); tr.add_argument("--issue")
    sub.add_parser("report")
    a = ap.parse_args(argv)
    inbox = pathlib.Path(a.inbox)

    if a.cmd == "check":
        bad = 0
        for p in candidates(a.files):
            try:
                w = validate(load(p))
                print(f"ok      {p}" + (f"  (warning: {', '.join(w)})" if w else ""))
            except Refused as e:
                bad += 1
                print(f"refused {p}: {e}")
        return 1 if bad else 0
    if a.cmd == "ingest":
        filed, dupes, refused = ingest(a.paths, inbox)
        for rid, w in filed:
            print(f"filed   {rid[:8]}" + (f"  (warning: {', '.join(w)})" if w else ""))
        for rid in dupes:
            print(f"already {rid[:8]}")
        for p, why in refused:
            print(f"refused {p}: {why}")
        print(f"{len(filed)} filed, {len(dupes)} already in, {len(refused)} refused")
        return 1 if refused else 0
    if a.cmd == "pull":
        repo = a.repo or origin_repo()
        filed, dupes, refused, failed = pull(repo, inbox)
        for rid, w in filed:
            print(f"filed   {rid[:8]}" + (f"  (warning: {', '.join(w)})" if w else ""))
        for p, why in refused:
            print(f"refused {pathlib.Path(p).name}: {why}")
        for u, why in failed:
            print(f"failed  {u}: {why}")
        print(f"{repo}: {len(filed)} filed, {len(dupes)} already in, {len(refused)} refused, {len(failed)} could not be downloaded")
        return 1 if refused or failed else 0
    if a.cmd == "list":
        t = read_triage(inbox)
        for r in sorted(reports(inbox), key=lambda r: r["created"]):
            st = t.get(r["id"], {}).get("status", "new")
            if (a.status and st != a.status) or (a.kind and r["kind"] != a.kind) or (a.build and r["app"]["build"] != a.build):
                continue
            print(f"{r['id'][:8]}  {r['created'][:10]}  {r['kind']:<9} b{r['app']['build']:<4} {st:<9} {r['message'].strip().splitlines()[0][:70]}")
        return 0
    if a.cmd == "show":
        t = read_triage(inbox)
        rid = find(a.id, t)
        print(json.dumps({"report": json.loads((inbox / "reports" / f"{rid}.json").read_text()), "triage": t[rid]}, indent=2))
        return 0
    if a.cmd == "triage":
        rid = set_status(inbox, a.id, a.status, a.note, a.issue)
        print(f"{rid[:8]} is {a.status}")
        return 0
    if a.cmd == "report":
        md, pg = write_report(inbox)
        print(f"wrote {md}\nwrote {pg}")
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
