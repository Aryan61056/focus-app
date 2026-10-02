#!/usr/bin/env python3
"""Static guard for the engine modules (FocusBrain, FocusJudge, FocusUI): no networking, no URL opening, no logging
of anything, no model other than Apple's system model. Findings F2, F8 and F26 in docs/SECURITY-REVIEW.md.

This is a source scan. It does NOT prove isolation and does NOT lift the ban on "OS-enforced" or "cannot reach the
network" in user-facing text; that waits for tests T1 to T4. It only stops us from adding the obvious ways out by accident.
Usage: tools/check_privacy.py [--self-test]
"""
from __future__ import annotations
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODULES = ["mac/Sources/FocusBrain", "mac/Sources/FocusJudge", "mac/Sources/FocusUI", "mac/Sources/FocusSense"]

RULES = [
    (r"\bURLSession\b|\bURLRequest\b|\bNWConnection\b|\bNWPathMonitor\b|\bCFSocket\b|\bCFStream\b|\bCFNetwork\b|URLSessionWebSocketTask",
     "networking API (F2)"),
    (r"^\s*(@_exported\s+)?import\s+(Network|WebKit|SafariServices|MultipeerConnectivity|CloudKit|Social)\b", "networking-capable framework (F2)"),
    (r"NSWorkspace\.shared\.open\(|NSWorkspace\.shared\.openApplication|\bopenURL\b|\bNSSharingService\b|\bNSPasteboard\b|UIPasteboard",
     "can open URLs or move text out through the OS (F2)"),
    (r"(?<![A-Za-z])print\(|\bdebugPrint\(|\bdump\(|\bNSLog\(|\bos_log\(|\bLogger\(|\bOSLog\b|\bos\.Logger\b|\bfputs\(",
     "logging of any kind: screen-derived text must never be logged (F26)"),
    (r"LanguageModelSession\([^)]*\bmodel:", "model other than SystemLanguageModel.default (F8)"),
    (r"\bSystemLanguageModel\((?!\))|SystemLanguageModel\.init\(|\bPrivateCloudCompute|\bConversationalLanguageModel\b", "non-default or non-local model (F8)"),
    (r"https?://[A-Za-z0-9]", "hard-coded URL with a host"),
    (r"\bCGImageDestination|\bpngData\(|\bjpegData\(|\btiffRepresentation\b|\bbitmapRepresentation|representation\(using:", "encodes an image, which could be saved: pictures stay in memory (principle 2)"),
]

def strip_comments(line: str) -> str:
    return re.sub(r"(?<![:\"A-Za-z])//.*$", "", line)   # keeps the // inside "https://"

def scan_text(name: str, text: str) -> list:
    out = []
    for n, raw in enumerate(text.splitlines(), 1):
        line = strip_comments(raw)
        if not line.strip(): continue
        for pat, why in RULES:
            if re.search(pat, line):
                out.append(f"{name}:{n}: {why}: {raw.strip()}")
    return out

def scan_repo() -> list:
    findings = []
    for m in MODULES:
        for p in sorted((ROOT / m).rglob("*.swift")):
            findings += scan_text(str(p.relative_to(ROOT)), p.read_text())
    return findings

def self_test() -> int:
    bad = {
        "net": "let s = URLSession.shared", "imp": "import Network", "open": "NSWorkspace.shared.open(url)",
        "log": 'print("title: \\(t)")', "model": "LanguageModelSession(model: other, instructions: x)",
        "url": 'let u = "https://example.com"', "cloud": "let m = PrivateCloudCompute()", "img": "let d = img.pngData()",
    }
    ok = ["let session = LanguageModelSession(instructions: x)", "switch SystemLanguageModel.default.availability {}", "// print(\"x\") in a comment", "let printable = 1"]
    failed = [k for k, v in bad.items() if not scan_text(k, v)] + [o for o in ok if scan_text("ok", o)]
    if failed:
        print("self-test FAILED for:", failed); return 1
    print(f"self-test ok ({len(bad)} bad lines caught, {len(ok)} clean lines passed)"); return 0

if __name__ == "__main__":
    if "--self-test" in sys.argv: sys.exit(self_test())
    f = scan_repo()
    for x in f: print(x)
    n = sum(len(list((ROOT / m).rglob("*.swift"))) for m in MODULES)
    print(f"{len(f)} finding(s) across {n} Swift files in {', '.join(m.split('/')[-1] for m in MODULES)}")
    sys.exit(1 if f else 0)
