"""Synthetic screenshot -> OCR text, via the shotgen Swift helper (Apple Vision framework).

PNGs go to eval/.cache/shots (gitignored). They are rendered from scenario text, never from a real screen.
"""
from __future__ import annotations

import json
import os
import subprocess
from typing import Dict, List

from .backends import EVAL_DIR, ensure_built
from .scenarios import Scenario

SRC = os.path.join(EVAL_DIR, "swift", "shotgen", "main.swift")
BIN = os.path.join(EVAL_DIR, ".build", "shotgen")
SHOTS = os.path.join(EVAL_DIR, ".cache", "shots")


def ocr_texts(items: List[Scenario]) -> Dict[str, str]:
    ensure_built(SRC, BIN)
    payload = "".join(json.dumps({
        "id": s.id, "app": s.app, "title": s.window_title, "url": s.url, "text": s.window_text,
    }) + "\n" for s in items)
    out = subprocess.run([BIN, SHOTS], input=payload, capture_output=True, text=True, check=True).stdout
    texts = {}
    for line in out.splitlines():
        row = json.loads(line)
        texts[row["id"]] = row.get("ocr_text", "")
    return texts
