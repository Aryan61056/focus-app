"""Stage 0 (sensitive-window exclusion) and Stage 1 (deterministic project rules).

Spike-grade: the sensitive lists are illustrative, not a shipped policy.
"""
from __future__ import annotations

import os
from typing import Optional, Tuple
from urllib.parse import urlparse

from .scenarios import Scenario

SENSITIVE_APPS = {"1password", "bitwarden", "keychain access", "dashlane", "lastpass"}
SENSITIVE_DOMAINS = {"chase.com", "bankofamerica.com", "wellsfargo.com", "paypal.com"}
PRIVATE_TITLE_MARKERS = ("private browsing", "incognito", "inprivate")


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
