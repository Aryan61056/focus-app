"""Runs one scenario through stage 0 (sensitive), stage 1 (rules), stage 3 (text judge).

Stage 2 (embedding relevance) is not built yet; see eval/README.md.
"""
from __future__ import annotations

from typing import Callable, List, Optional

from . import prompts, rules
from .backends import Backend
from .scenarios import Scenario


def run(
    scenarios: List[Scenario],
    backend: Backend,
    use_rules: bool = True,
    text_mode: str = "full",
    text_for: Optional[Callable[[Scenario], str]] = None,
    progress: Optional[Callable[[int, int, Scenario], None]] = None,
) -> List[dict]:
    """text_mode: 'full' (title + url + window text), 'titles' (no window text),
    'ocr' (window text replaced by text_for(scenario), e.g. OCR of a synthetic screenshot)."""
    results = []
    for i, s in enumerate(scenarios):
        if progress:
            progress(i, len(scenarios), s)
        row = {
            "id": s.id, "category": s.category, "difficulty": s.difficulty,
            "gold": s.label, "tags": s.tags, "title": s.window_title,
        }
        if use_rules and rules.is_sensitive(s):
            row.update(pred="unsure", confidence=None, stage="sensitive", reason="sensitive window, not read")
        elif use_rules and rules.stage1(s):
            label, rule = rules.stage1(s)
            row.update(pred=label, confidence=1.0, stage="rule", reason=rule)
        else:
            include_text = text_mode != "titles"
            override = text_for(s) if (text_mode == "ocr" and text_for) else ""
            if text_mode == "ocr" and not override:
                include_text = False
            instructions, prompt = prompts.build(s, include_text=include_text, text_override=override, version=backend.prompt_version)
            v = backend.judge(s, instructions, prompt)
            row.update(
                pred=v.label, confidence=v.confidence, stage="model", reason=v.reason,
                category_guess=v.category, content_kind=v.content_kind,
                latency_ms=v.latency_ms, error=v.error,
            )
        results.append(row)
    return results
