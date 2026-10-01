"""Prompt construction, shared by every model backend so they are compared like for like."""
from __future__ import annotations

import os
from typing import Tuple

from .scenarios import Scenario

PROMPT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "core", "prompts")


def _read(name: str) -> str:
    """Instruction text lives in core/prompts so the Swift port uses exactly the same words."""
    with open(os.path.join(PROMPT_DIR, name), encoding="utf-8") as fh:
        return fh.read()


MAX_TEXT_CHARS = 1200  # the Apple system model has a ~4K-token context window

INSTRUCTIONS = _read("instructions_v1.txt")


INSTRUCTIONS_V2 = _read("instructions_v2.txt")

RELATION_TO_LABEL = {
    "directly_serves": "on_task",
    "supporting": "on_task",
    "neutral": "unsure",
    "unclear": "unsure",
    "different_activity": "off_task",
}


def instructions_for(version: str) -> str:
    return INSTRUCTIONS_V2 if version == "v2" else INSTRUCTIONS


def _one_line(value: str) -> str:
    """Screen-derived single-line fields must not be able to start new prompt lines."""
    return " ".join(value.split())


def _neutralize(text: str) -> str:
    """Screen text must not be able to close or reopen the <window_text> block."""
    return text.replace("<window_text", "< window_text").replace("</window_text", "< /window_text")


def build_prompt(s: Scenario, include_text: bool = True, text_override: str = "") -> str:
    lines = ["Task: %s" % s.task]
    context = s.project.get("context", "") if s.project else ""
    if context:
        lines.append("Project context: %s" % context)
    lines.append("")
    lines.append("Window right now:")
    lines.append("app: %s" % _one_line(s.app))
    lines.append("title: %s" % _one_line(s.window_title))
    if s.url:
        lines.append("url: %s" % _one_line(s.url))
    if s.document_path:
        lines.append("document: %s" % _one_line(s.document_path))
    text = text_override if text_override else (s.window_text if include_text else "")
    if text:
        lines.append("<window_text>")
        lines.append(_neutralize(text[:MAX_TEXT_CHARS]))
        lines.append("</window_text>")
    return "\n".join(lines)


def build(s: Scenario, include_text: bool = True, text_override: str = "", version: str = "v1") -> Tuple[str, str]:
    return instructions_for(version), build_prompt(s, include_text, text_override)
