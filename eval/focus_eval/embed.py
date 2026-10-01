"""Stage 2 relevance: cosine distance between the task and a window description (Apple built-in embeddings)."""
from __future__ import annotations

import json
import os
import subprocess
from typing import Dict, List
from urllib.parse import urlparse

from .backends import EVAL_DIR, ensure_built
from .scenarios import Scenario

SRC = os.path.join(EVAL_DIR, "swift", "embed", "main.swift")
BIN = os.path.join(EVAL_DIR, ".build", "embed")


def window_description(s: Scenario, with_text: bool) -> str:
    parts = [s.app, s.window_title]
    if s.url:
        u = urlparse(s.url)
        parts.append((u.hostname or "") + u.path.replace("/", " ").replace("-", " ").replace("_", " "))
    if with_text:
        parts.append(s.window_text[:300])
    return ". ".join(p for p in parts if p)


def distances(items: List[Scenario], with_text: bool = True) -> Dict[str, float]:
    ensure_built(SRC, BIN)
    payload = "".join(json.dumps({
        "id": s.id, "doc": window_description(s, with_text),
        "task": s.task + (". " + s.project["context"] if s.project.get("context") else ""),
    }) + "\n" for s in items)
    out = subprocess.run([BIN], input=payload, capture_output=True, text=True, check=True).stdout.splitlines()
    return {json.loads(l)["id"]: json.loads(l)["distance"] for l in out[1:]}
