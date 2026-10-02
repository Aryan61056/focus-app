"""Model backends. Each takes (instructions, prompt) and returns a Verdict.

oracle, always_unsure and lexical exist to sanity-check the harness and set a floor.
fm_swift runs Apple's on-device system model through the FoundationModels framework.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
from dataclasses import dataclass
from typing import Optional

from .scenarios import Scenario

HERE = os.path.dirname(os.path.abspath(__file__))
EVAL_DIR = os.path.dirname(HERE)
FMJUDGE_SRC = os.path.join(EVAL_DIR, "swift", "fmjudge", "main.swift")
FMJUDGE_BIN = os.path.join(EVAL_DIR, ".build", "fmjudge")
XCODE_DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer"


def ensure_built(src: str, binary: str) -> None:
    """Compile a Swift helper with swiftc when missing or stale."""
    if os.path.exists(binary) and os.path.getmtime(binary) >= os.path.getmtime(src):
        return
    os.makedirs(os.path.dirname(binary), exist_ok=True)
    # Xcode's python3 shim exports SDKROOT pointing at the Command Line Tools SDK, which can be
    # newer than the compiler. Drop it and pin Xcode so swiftc picks the matching SDK.
    env = dict(os.environ, DEVELOPER_DIR=os.environ.get("DEVELOPER_DIR", XCODE_DEVELOPER_DIR))
    env.pop("SDKROOT", None)
    subprocess.run(["swiftc", "-O", src, "-o", binary], check=True, env=env)


@dataclass
class Verdict:
    label: str
    confidence: Optional[float] = None  # 0..1
    reason: str = ""
    category: str = ""
    content_kind: str = ""
    latency_ms: Optional[float] = None
    error: Optional[str] = None  # set when the model refused or failed; label is then `unsure`


class Backend:
    name = "base"
    prompt_version = "v1"

    def start(self) -> None:
        pass

    def close(self) -> None:
        pass

    def judge(self, s: Scenario, instructions: str, prompt: str) -> Verdict:
        raise NotImplementedError


class Oracle(Backend):
    name = "oracle"

    def judge(self, s, instructions, prompt):
        return Verdict(s.label, 1.0, "gold label", latency_ms=0.0)


class AlwaysUnsure(Backend):
    name = "always_unsure"

    def judge(self, s, instructions, prompt):
        return Verdict("unsure", 0.5, "never nudges", latency_ms=0.0)


_STOP = set("a an the and or of to in on for with my our is are be this that it as at by from your".split())


def _tokens(text: str) -> set:
    return {t for t in re.findall(r"[a-z0-9]+", text.lower()) if len(t) > 2 and t not in _STOP}


class Lexical(Backend):
    """Keyword-overlap baseline: the floor a real model has to beat."""

    name = "lexical"

    def judge(self, s, instructions, prompt):
        task = _tokens(s.task)
        seen = _tokens(" ".join([s.window_title, s.url, s.document_path, s.window_text]))
        overlap = len(task & seen)
        if overlap >= 2:
            return Verdict("on_task", 0.7, "keyword overlap", latency_ms=0.0)
        if overlap == 0:
            return Verdict("off_task", 0.6, "no keyword overlap", latency_ms=0.0)
        return Verdict("unsure", 0.5, "weak overlap", latency_ms=0.0)


class FMSwift(Backend):
    """Apple on-device system model through a small compiled Swift helper (JSON lines over pipes)."""

    def __init__(self, order: str = "reason-first"):
        self.order = order
        self.name = "fm_swift:" + order
        self.prompt_version = "v2" if order in ("relation", "relation-reasoned") else "v1"
        self.proc: Optional[subprocess.Popen] = None

    def start(self) -> None:
        ensure_built(FMJUDGE_SRC, FMJUDGE_BIN)
        self.proc = subprocess.Popen(
            [FMJUDGE_BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1
        )
        ready = self.proc.stdout.readline()
        info = json.loads(ready)
        if info.get("status") != "available":
            raise RuntimeError("system model unavailable: %s" % info)

    def extra_request(self, s: Scenario) -> dict:
        return {}

    def close(self) -> None:
        if self.proc:
            self.proc.stdin.close()
            self.proc.wait(timeout=10)
            self.proc = None

    def judge(self, s, instructions, prompt):
        assert self.proc is not None
        req = {"id": s.id, "instructions": instructions, "prompt": prompt, "order": self.order}
        req.update(self.extra_request(s))
        t0 = time.time()
        self.proc.stdin.write(json.dumps(req) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        wall = (time.time() - t0) * 1000.0
        if not line:
            return Verdict("unsure", error="helper exited", latency_ms=wall)
        out = json.loads(line)
        if out.get("error"):
            return Verdict("unsure", error="%s: %s" % (out["error"], out.get("detail", "")), latency_ms=wall)
        if "relation" in out:
            from .prompts import RELATION_TO_LABEL
            label = RELATION_TO_LABEL.get(out["relation"])
            if label is None:
                return Verdict("unsure", error="unknown relation %r" % out["relation"], latency_ms=wall)
            return Verdict(label, None, out.get("reason", ""), out["relation"], out.get("topic", ""), latency_ms=wall)
        try:
            conf = None if out.get("confidence") is None else float(out["confidence"])
        except (TypeError, ValueError):
            conf = None
        return Verdict(
            label=out["label"],
            confidence=None if conf is None else max(0.0, min(1.0, conf / 100.0)),
            reason=out.get("reason", ""),
            category=out.get("category", ""),
            content_kind=out.get("content_kind", ""),
            latency_ms=wall,
        )


MODELS_DIR = os.path.join(EVAL_DIR, ".cache", "models")
MLX_TEXT_MODEL = os.path.join(MODELS_DIR, "Qwen3-4B-Instruct-2507-4bit")
MLX_JUDGE = os.path.join(EVAL_DIR, "mlx", "mlx_judge.py")


class MLXText(FMSwift):
    """Local MLX text model through mlx/mlx_judge.py in the uv environment (weights loaded from disk, offline)."""

    def __init__(self, order: str = "reason-first", model_dir: str = MLX_TEXT_MODEL):
        super().__init__(order)
        self.model_dir = model_dir
        self.name = "mlx_text:%s:%s" % (os.path.basename(model_dir), order)

    def start(self) -> None:
        env = dict(os.environ, HF_HUB_OFFLINE="1")
        self.proc = subprocess.Popen(
            ["uv", "run", "--project", EVAL_DIR, "python", MLX_JUDGE, self.model_dir],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1, env=env,
        )
        info = json.loads(self.proc.stdout.readline())
        if info.get("status") != "available":
            raise RuntimeError("mlx model unavailable: %s" % info)


MLX_VLM_MODEL = os.path.join(MODELS_DIR, "Qwen3-VL-4B-Instruct-4bit")
MLX_VLM_JUDGE = os.path.join(EVAL_DIR, "mlx", "mlx_vlm_judge.py")
SHOTS_DIR = os.path.join(EVAL_DIR, ".cache", "shots")


class MLXVision(MLXText):
    """Local MLX vision-language model reading a synthetic screenshot (render it first with focus_eval.ocr)."""

    def __init__(self, order: str = "reason-first", model_dir: str = MLX_VLM_MODEL):
        super().__init__(order, model_dir)
        self.name = "mlx_vlm:%s:%s" % (os.path.basename(model_dir), order)

    def start(self) -> None:
        env = dict(os.environ, HF_HUB_OFFLINE="1")
        self.proc = subprocess.Popen(
            ["uv", "run", "--project", EVAL_DIR, "python", MLX_VLM_JUDGE, self.model_dir],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1, env=env,
        )
        info = json.loads(self.proc.stdout.readline())
        if info.get("status") != "available":
            raise RuntimeError("mlx vision model unavailable: %s" % info)

    def extra_request(self, s: Scenario) -> dict:
        return {"image": os.path.join(SHOTS_DIR, s.id + ".png")}


def make(name: str, order: str = "reason-first") -> Backend:
    if name == "oracle":
        return Oracle()
    if name == "always_unsure":
        return AlwaysUnsure()
    if name == "lexical":
        return Lexical()
    if name == "fm_swift":
        return FMSwift(order)
    if name == "mlx_text":
        return MLXText(order)
    if name == "mlx_vlm":
        return MLXVision(order)
    raise ValueError("unknown backend %r" % name)
