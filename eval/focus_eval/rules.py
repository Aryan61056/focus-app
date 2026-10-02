"""Stage 0 (sensitive-window exclusion) and Stage 1 (deterministic project rules).

Spike-grade: the sensitive lists are illustrative, not a shipped policy.
"""
from __future__ import annotations

import os
import re
import unicodedata
from typing import Optional, Tuple
from urllib.parse import unquote, urlparse

from .scenarios import Scenario

SENSITIVE_APPS = {
    "1password", "1password 7", "bitwarden", "keychain access", "passwords", "dashlane", "lastpass",
    "keepassxc", "keepass", "keepassium", "enpass", "nordpass", "proton pass", "roboform", "keeper",
    "secrets", "authy", "microsoft authenticator", "yubico authenticator",
}
SENSITIVE_DOMAINS = {
    "chase.com", "bankofamerica.com", "wellsfargo.com", "paypal.com", "citi.com", "capitalone.com",
    "usbank.com", "schwab.com", "fidelity.com", "vanguard.com", "coinbase.com", "venmo.com",
    "wise.com", "revolut.com", "1password.com", "bitwarden.com", "lastpass.com", "proton.me",
}
PRIVATE_TITLE_MARKERS = ("private browsing", "incognito", "inprivate", "private window", "(private)")


def _host_and_path(url: str) -> Tuple[str, str]:
    if not url:
        return "", ""
    parsed = urlparse(url if "://" in url else "https://" + url)
    return (parsed.hostname or "").lower().lstrip("."), parsed.path


def _domain_matches(entry: str, url: str) -> bool:
    """entry is 'example.com' or 'example.com/path/prefix'."""
    host, path = _host_and_path(url)
    if not host:
        return False
    entry_host, _, entry_path = entry.lower().partition("/")
    if not (host == entry_host or host.endswith("." + entry_host)):
        return False
    return not entry_path or path.lower().lstrip("/").startswith(entry_path.strip("/"))


def _norm_path(p: str) -> str:
    return os.path.normpath(p.replace("~", "/HOME")) if p else ""


def is_sensitive(s: Scenario) -> bool:
    if s.app.lower() in SENSITIVE_APPS:
        return True
    title = s.window_title.lower()
    if any(m in title for m in PRIVATE_TITLE_MARKERS):
        return True
    host, _ = _host_and_path(s.url)
    return any(host == d or host.endswith("." + d) for d in SENSITIVE_DOMAINS)


def stage1(s: Scenario) -> Optional[Tuple[str, str]]:
    """Return (label, rule name) if a project rule decides, else None. Deny beats allow."""
    p = s.project
    if not p:
        return None
    if s.app.lower() in [a.lower() for a in p.get("always_off_apps", [])]:
        return "off_task", "always_off_app"
    if any(_domain_matches(d, s.url) for d in p.get("always_off_domains", [])):
        return "off_task", "always_off_domain"
    if s.app.lower() in [a.lower() for a in p.get("always_allow_apps", [])]:
        return "on_task", "always_allow_app"
    if any(_domain_matches(d, s.url) for d in p.get("always_allow_domains", [])):
        return "on_task", "always_allow_domain"
    if any(_domain_matches(d, s.url) for d in p.get("linked_domains", [])):
        return "on_task", "linked_domain"
    doc = _norm_path(s.document_path)
    if doc:
        for link in p.get("linked_paths", []):
            base = _norm_path(link)
            if doc == base or doc.startswith(base.rstrip("/") + "/"):
                return "on_task", "linked_path"
    return None


# Mirror of mac/Sources/FocusJudge/Rules.swift `isNeverJudged` (owner approved the default list on 2026-10-01).
# tests/test_rules.py checks the list against the Swift source so the two cannot drift.
DEFAULT_NEVER_JUDGED_APPS = ["Messages", "WhatsApp", "Telegram", "Signal", "Music", "Spotify", "Podcasts", "Tidal", "Pandora"]
BLANK_PAGE_TITLES = {"new tab", "start page", "untitled", "favorites", "top sites", "new window"}


def is_never_judged(s: Scenario, apps=DEFAULT_NEVER_JUDGED_APPS) -> bool:
    """Personal messaging, music and blank pages are not read and not counted. A project rule wins, so callers check stage1 first."""
    if s.app.lower() in [a.lower() for a in apps]:
        return True
    host, _ = _host_and_path(s.url)
    blank_url = (not s.url) or s.url.startswith(("about:blank", "chrome://newtab", "favorites://")) or host == "newtab"
    return s.window_title.strip().lower() in BLANK_PAGE_TITLES and blank_url and not s.document_path


# Mirror of mac/Sources/FocusJudge/Rules.swift `injectionPatterns` (prompt-injection guard, docs/T7-injection.md).
# tests/test_rules.py checks the two lists are identical.
INJECTION_PATTERNS = [
    r"\b(?:off|on)_task\b",
    r"\b(?:different_activity|directly_serves)\b",
    r"ignore\s+(?:all\s+|any\s+|the\s+|your\s+)*(?:previous|prior|above|earlier)\s+(?:instructions?|rules?|prompts?)",
    r"disregard\s+(?:all\s+|any\s+|the\s+|your\s+)*(?:previous\s+|prior\s+|above\s+|earlier\s+)?(?:instructions?|rules?)",
    r"ignore\s+the\s+task",
    r"note\s+to\s+(?:the\s+)?(?:ai|assistant|model|llm)",
    r"\[(?:system|assistant|developer)\]",
    r"(?:^|[.!?\n])\s*(?:system|assistant|developer)\s*:",
    r"classification\s+rules",
    r"</?window_text",
]
_INJECTION_RE = [re.compile(p, re.IGNORECASE) for p in INJECTION_PATTERNS]


def normalized_for_scan(text: str) -> str:
    """Unicode compatibility form, zero-width characters removed, percent-escapes decoded (mirror of Rules.normalizedForScan in Swift)."""
    folded = "".join(c for c in unicodedata.normalize("NFKC", text) if c not in "\u200b\u200c\u200d\u200e\u200f\u2060\ufeff\u00ad")
    return unquote(folded)


def looks_injected(s: Scenario) -> bool:
    """Window text that talks to the AI. Such windows are not judged: they come back unsure."""
    fields = [normalized_for_scan(f) for f in (s.window_title, s.url, s.document_path, s.window_text)]
    return any(r.search(f) for f in fields for r in _INJECTION_RE)
