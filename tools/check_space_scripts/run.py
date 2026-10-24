"""Runs the AppleScript that Hushd generates for Arc and Dia against stand-in apps that follow the two dictionaries.

What this proves: the scripts' own logic (look in the space you worked in first, fall back to any space, bring the space and the tab
forward, bring the window to the front, say "none" or "changed" when there is nothing to do, escaping of quotes and backslashes, private
windows reading nothing) works when run by a real Cocoa scripting layer. What it does not prove: how the real browsers behave. Arc and Dia
need Automation permission, which an agent cannot grant, so this has never run against either (tools/check_space_browsers.sh does that,
read-only, once you allow it). The stand-ins talk to themselves, so no permission prompt appears and nothing of yours is touched.

Usage: tools/check_space_scripts.sh
"""
import json, subprocess, re, sys, os, shutil, tempfile, platform
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dictionaries import arc as ARC_SDEF, dia as DIA_SDEF
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DUMP = os.path.join(ROOT, "mac", ".build", "debug", "script-dump")
WORK = tempfile.mkdtemp(prefix="focus-space-scripts-")

def build_fakes():
    """Compiles FakeSpaces.swift once and wraps it in two bundles (dev.focus.fakearc and dev.focus.fakedia) with their own dictionaries."""
    env = {k: v for k, v in os.environ.items() if k != "SDKROOT"}   # Xcode's python shim exports a newer SDK than the compiler (see CLAUDE.md)
    exe = os.path.join(WORK, "fake")
    subprocess.run(["swiftc", "-target", platform.machine() + "-apple-macos14.0", "-o", exe, os.path.join(HERE, "FakeSpaces.swift")], check=True, env=env)
    for kind, sdef in (("arc", ARC_SDEF), ("dia", DIA_SDEF)):
        app = os.path.join(WORK, f"Fake{kind}.app")
        os.makedirs(os.path.join(app, "Contents", "MacOS")); os.makedirs(os.path.join(app, "Contents", "Resources"))
        shutil.copy(exe, os.path.join(app, "Contents", "MacOS", "fake"))
        open(os.path.join(app, "Contents", "Resources", "Fake.sdef"), "w").write(sdef)
        open(os.path.join(app, "Contents", "Info.plist"), "w").write(f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.focus.fake{kind}</string><key>CFBundleName</key><string>Fake{kind}</string>
<key>CFBundleExecutable</key><string>fake</string><key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/><key>NSPrincipalClass</key><string>FApp</string>
<key>NSAppleScriptEnabled</key><true/><key>OSAScriptingDefinition</key><string>Fake.sdef</string>
</dict></plist>
""")
        subprocess.run(["codesign", "--force", "-s", "-", app], check=True, capture_output=True)

def gen(*args): return subprocess.run([DUMP, *args], capture_output=True, text=True).stdout
def retarget(src, kind): return re.sub(r'application "(Arc|Dia)"', f'application id "dev.focus.fake{kind}"', src)

def tab(i, title, url): return {"id": i, "title": title, "url": url}
def arc_windows():
    return [
      {"id": "w1", "activeSpace": "s-work", "spaces": [
         {"id": "s-work", "title": "Work", "selected": "t2", "tabs": [tab("t1", "Lecture notes", "https://notes.example.com/lec"), tab("t2", "Docs", "https://docs.example.com/a")]},
         {"id": "s-play", "title": "Play", "selected": "t3", "tabs": [tab("t3", "Video", "https://youtube.com/watch?v=1"), tab("t4", "Lecture notes copy", "https://notes.example.com/lec?x=1")]}]},
      {"id": "w2", "activeSpace": "s-other", "spaces": [
         {"id": "s-other", "title": "Other", "tabs": [tab("t5", 'He said "hi" \\ ok', "https://quote.example.com/q")]}]},
    ]
def dia_windows():
    return [
      {"id": "w1", "activeProfile": "Work", "profiles": [
         {"name": "Work", "selected": "t2", "tabs": [tab("t1", "Lecture notes", "https://notes.example.com/lec"), tab("t2", "Docs", "https://docs.example.com/a")]},
         {"name": "Personal", "selected": "t3", "tabs": [tab("t3", "Video", "https://youtube.com/watch?v=1"), tab("t4", "Lecture notes copy", "https://notes.example.com/lec?x=1")]}]},
      {"id": "w2", "activeProfile": "Other", "profiles": [
         {"name": "Other", "tabs": [tab("t5", 'He said "hi" \\ ok', "https://quote.example.com/q")]}]},
    ]

cases = []
def add(kind, name, windows, script, result, **expect):
    cases.append({"kind": kind, "name": name, "windows": windows, "script": retarget(script, kind), "expect": dict(result=result, **expect)})

# ---- Arc
A = "Arc"
add("arc", "arc: same page, space you worked in is preferred (work)", arc_windows(), gen("switchTo", A, "https://notes.example.com/lec", "s-work"), "ok", win="w1", space="s-work", tab="t1")
add("arc", "arc: same page, space you worked in is preferred (play)", arc_windows(), gen("switchTo", A, "https://notes.example.com/lec", "s-play"), "ok", win="w1", space="s-play", tab="t4")
add("arc", "arc: page only in another space is still found", arc_windows(), gen("switchTo", A, "https://docs.example.com/a", "s-play"), "ok", win="w1", space="s-work", tab="t2")
add("arc", "arc: unknown space falls back to any space", arc_windows(), gen("switchTo", A, "https://docs.example.com/a", "s-gone"), "ok", win="w1", space="s-work", tab="t2")
add("arc", "arc: no space recorded finds the first match", arc_windows(), gen("switchTo", A, "https://notes.example.com/lec", ""), "ok", win="w1", space="s-work", tab="t1")
add("arc", "arc: page nowhere says none and changes nothing", arc_windows(), gen("switchTo", A, "https://nowhere.example.com/x", "s-work"), "none", win="w1", space="s-work", tab="t2")
add("arc", "arc: page in another window brings that window to the front", arc_windows(), gen("switchTo", A, "https://quote.example.com/q", "s-other"), "ok", win="w2", space="s-other", tab="t5", order=["w2", "w1"])
add("arc", "arc: by title", arc_windows(), gen("switchToTitle", A, "Lecture notes copy", "s-play"), "ok", win="w1", space="s-play", tab="t4")
add("arc", "arc: by title with quotes and a backslash", arc_windows(), gen("switchToTitle", A, 'He said "hi" \\ ok', ""), "ok", win="w2", space="s-other", tab="t5")
add("arc", "arc: title too short is refused before any script", arc_windows(), gen("switchToTitle", A, "Docs", ""), "NIL", win="w1", space="s-work", tab="t2")
add("arc", "arc: current tab and space", arc_windows(), gen("currentTab", A), "https://docs.example.com/a\ts-work")
inc = arc_windows(); inc[0]["mode"] = "incognito"
add("arc", "arc: a private window reports nothing", inc, gen("currentTab", A), "")
add("arc", "arc: no windows reports nothing", [], gen("currentTab", A), "")
add("arc", "arc: no windows, switch says none", [], gen("switchTo", A, "https://docs.example.com/a", "s-work"), "none")
# ---- Dia
D = "Dia"
add("dia", "dia: same page, profile you worked in is preferred (Work)", dia_windows(), gen("switchTo", D, "https://notes.example.com/lec", "Work"), "ok", win="w1", profile="Work", tab="t1")
add("dia", "dia: same page, profile you worked in is preferred (Personal)", dia_windows(), gen("switchTo", D, "https://notes.example.com/lec", "Personal"), "ok", win="w1", profile="Personal", tab="t4")
add("dia", "dia: page only in another profile is still found", dia_windows(), gen("switchTo", D, "https://docs.example.com/a", "Personal"), "ok", win="w1", profile="Work", tab="t2")
add("dia", "dia: unknown profile falls back to any", dia_windows(), gen("switchTo", D, "https://docs.example.com/a", "Gone"), "ok", win="w1", profile="Work", tab="t2")
add("dia", "dia: page nowhere says none", dia_windows(), gen("switchTo", D, "https://nowhere.example.com/x", "Work"), "none", win="w1", profile="Work", tab="t2")
add("dia", "dia: page in another window brings that window to the front", dia_windows(), gen("switchTo", D, "https://quote.example.com/q", "Other"), "ok", win="w2", profile="Other", tab="t5", order=["w2", "w1"])
add("dia", "dia: by title", dia_windows(), gen("switchToTitle", D, "Lecture notes copy", "Personal"), "ok", win="w1", profile="Personal", tab="t4")
add("dia", "dia: by title with quotes and a backslash", dia_windows(), gen("switchToTitle", D, 'He said "hi" \\ ok', ""), "ok", win="w2", profile="Other", tab="t5")
add("dia", "dia: current profile only, never an address", dia_windows(), gen("currentTab", D), "\tWork")
add("dia", "dia: no windows reports nothing", [], gen("currentTab", D), "")

# ---- close
add("arc", "arc close: the open tab is closed when it is still the page", arc_windows(), gen("close", A, "https://docs.example.com/a"), "ok", gone="t2")
add("arc", "arc close: a different page is left alone", arc_windows(), gen("close", A, "https://notes.example.com/lec"), "changed", kept="t2")
add("arc", "arc close: no windows says changed", [], gen("close", A, "https://docs.example.com/a"), "changed")
add("dia", "dia close: the open tab is closed when it is still the page", dia_windows(), gen("close", D, "https://docs.example.com/a"), "ok", gone="t2")
add("dia", "dia close: a different page is left alone", dia_windows(), gen("close", D, "https://notes.example.com/lec"), "changed", kept="t2")
add("dia", "dia close: no windows says changed", [], gen("close", D, "https://docs.example.com/a"), "changed")

build_fakes()
results = {}
for kind in ("arc", "dia"):
    mine = [c for c in cases if c["kind"] == kind]
    inp = os.path.join(WORK, f"cases-{kind}.json"); out = os.path.join(WORK, f"out-{kind}.json")
    if os.path.exists(out): os.remove(out)
    json.dump([{"name": c["name"], "windows": c["windows"], "script": c["script"]} for c in mine], open(inp, "w"))
    subprocess.run(["open", "-g", "-n", "-W", os.path.join(WORK, f"Fake{kind}.app"), "--args", inp, out], timeout=120)
    results[kind] = json.load(open(out)) if os.path.exists(out) else []

failed = 0
for kind in ("arc", "dia"):
    mine = [c for c in cases if c["kind"] == kind]
    if len(results[kind]) != len(mine): print(f"{kind}: ran {len(results[kind])} of {len(mine)} cases"); failed += 1
    for c, r in zip(mine, results[kind]):
        e = c["expect"]; problems = []
        if e["result"] == "NIL":
            ok = c["script"].strip() == "NIL"; 
            if not ok: problems.append(f"expected no script, got one")
        else:
            if r.get("error"): problems.append("script error: " + r["error"])
            if r["result"] != e["result"]: problems.append(f"result {r['result']!r} wanted {e['result']!r}")
        fin = r["final"]; w0 = fin["windows"][0] if fin["windows"] else {}
        if "win" in e:
            if w0.get("id") != e["win"]: problems.append(f"front window {w0.get('id')} wanted {e['win']}")
            key = "space" if "space" in e else "profile"
            if w0.get(key) != e[key]: problems.append(f"{key} {w0.get(key)!r} wanted {e[key]!r}")
            if w0.get("tab") != e["tab"]: problems.append(f"tab {w0.get('tab')} wanted {e['tab']}")
        tabs = w0.get("tabs", [])
        if "gone" in e and e["gone"] in tabs: problems.append(f"tab {e['gone']} should have been closed")
        if "kept" in e and e["kept"] not in tabs: problems.append(f"tab {e['kept']} should not have been closed")
        if "order" in e and fin["order"] != e["order"]: problems.append(f"order {fin['order']} wanted {e['order']}")
        print(("PASS " if not problems else "FAIL ") + c["name"] + ("" if not problems else "  <- " + "; ".join(problems)))
        failed += bool(problems)
print("failures:", failed)
shutil.rmtree(WORK, ignore_errors=True)
sys.exit(1 if failed else 0)
