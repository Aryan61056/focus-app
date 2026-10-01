"""Scenario format: load and validate synthetic scenarios.

A scenario file is a JSON array of objects. See eval/README.md for the field list.
"""
from __future__ import annotations

import glob
import json
import os
from dataclasses import dataclass, field
from typing import Any, Dict, List

LABELS = ("on_task", "unsure", "off_task")
DIFFICULTIES = ("clear", "gray")
REQUIRED = ("id", "category", "difficulty", "task", "app", "window_title", "label", "notes")
PROJECT_KEYS = (
    "context",
    "linked_domains",
    "linked_paths",
    "always_allow_apps",
    "always_allow_domains",
    "always_off_apps",
    "always_off_domains",
)


class ScenarioError(ValueError):
    pass


@dataclass
class Scenario:
    id: str
    category: str
    difficulty: str
    task: str
    app: str
    window_title: str
    label: str
    notes: str
    url: str = ""
    document_path: str = ""
    window_text: str = ""
    project: Dict[str, Any] = field(default_factory=dict)
    tags: List[str] = field(default_factory=list)


def _validate_one(raw: Dict[str, Any], where: str) -> List[str]:
    problems = []
    for key in REQUIRED:
        if not isinstance(raw.get(key), str) or not raw[key].strip():
            problems.append("%s: missing or empty '%s'" % (where, key))
    if raw.get("label") not in LABELS:
        problems.append("%s: label must be one of %s" % (where, LABELS))
    if raw.get("difficulty") not in DIFFICULTIES:
        problems.append("%s: difficulty must be one of %s" % (where, DIFFICULTIES))
    for key in ("url", "document_path", "window_text"):
        if key in raw and not isinstance(raw[key], str):
            problems.append("%s: '%s' must be a string" % (where, key))
    project = raw.get("project", {})
    if not isinstance(project, dict):
        problems.append("%s: project must be an object" % where)
    else:
        for key, value in project.items():
            if key not in PROJECT_KEYS:
                problems.append("%s: unknown project key '%s'" % (where, key))
            elif key == "context" and not isinstance(value, str):
                problems.append("%s: project.context must be a string" % where)
            elif key != "context" and not (
                isinstance(value, list) and all(isinstance(v, str) for v in value)
            ):
                problems.append("%s: project.%s must be a list of strings" % (where, key))
    known = set(REQUIRED) | {"url", "document_path", "window_text", "project", "tags"}
    for key in raw:
        if key not in known:
            problems.append("%s: unknown field '%s'" % (where, key))
    return problems


def load_dir(path: str) -> List[Scenario]:
    """Load every *.json file in a directory. Raises ScenarioError listing all problems."""
    files = sorted(glob.glob(os.path.join(path, "*.json")))
    if not files:
        raise ScenarioError("no scenario files in %s" % path)
    problems: List[str] = []
    scenarios: List[Scenario] = []
    seen = set()
    for fpath in files:
        base = os.path.basename(fpath)
        with open(fpath, encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, list):
            problems.append("%s: top level must be an array" % base)
            continue
        for i, raw in enumerate(data):
            where = "%s[%d] (%s)" % (base, i, raw.get("id", "?") if isinstance(raw, dict) else "?")
            if not isinstance(raw, dict):
                problems.append("%s: not an object" % where)
                continue
            found = _validate_one(raw, where)
            if raw.get("id") in seen:
                found.append("%s: duplicate id" % where)
            seen.add(raw.get("id"))
            problems.extend(found)
            if not found:
                scenarios.append(Scenario(
                    id=raw["id"], category=raw["category"], difficulty=raw["difficulty"],
                    task=raw["task"], app=raw["app"], window_title=raw["window_title"],
                    label=raw["label"], notes=raw["notes"], url=raw.get("url", ""),
                    document_path=raw.get("document_path", ""),
                    window_text=raw.get("window_text", ""),
                    project=raw.get("project", {}), tags=raw.get("tags", []),
                ))
    if problems:
        raise ScenarioError("\n".join(problems))
    return scenarios
