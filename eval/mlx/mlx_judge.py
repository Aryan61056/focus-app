"""MLX text judge helper: same JSON-lines protocol as swift/fmjudge.

  uv run --project eval python eval/mlx/mlx_judge.py <model-dir>

Request:  {"id", "instructions", "prompt", "order": "reason-first" | "label-first" | "relation"}
Response: {"id", "label", "confidence", "reason"} | {"id", "relation", "topic", "reason"} | {"id", "error", "detail"}
Loads weights from a local directory only. Never touches the network.
"""
import json
import os
import re
import sys

os.environ.setdefault("HF_HUB_OFFLINE", "1")

from mlx_lm import generate, load  # noqa: E402
from mlx_lm.sample_utils import make_sampler  # noqa: E402

FORMATS = {
    "reason-first": '{"reason": "<=14 words", "label": "on_task|unsure|off_task", "confidence": <0-100>}',
    "label-first": '{"label": "on_task|unsure|off_task", "confidence": <0-100>, "reason": "<=14 words"}',
    "relation": '{"topic": "<=10 words", "relation": "directly_serves|supporting|neutral|unclear|different_activity", "reason": "<=14 words"}',
}


def emit(obj):
    print(json.dumps(obj), flush=True)


def parse(text):
    m = re.search(r"\{.*?\}", text, re.S)
    if not m:
        raise ValueError("no JSON object in output")
    return json.loads(m.group(0))


def main():
    model, tok = load(sys.argv[1])
    sampler = make_sampler(temp=0.0)
    emit({"status": "available", "model": os.path.basename(sys.argv[1].rstrip("/"))})
    for line in sys.stdin:
        req = json.loads(line)
        order = req.get("order", "reason-first")
        system = req["instructions"] + "\n\nReply with only one JSON object, no other text, in this shape:\n" + FORMATS[order]
        messages = [{"role": "system", "content": system}, {"role": "user", "content": req["prompt"]}]
        prompt = tok.apply_chat_template(messages, add_generation_prompt=True, tokenize=False)
        try:
            out = generate(model, tok, prompt=prompt, max_tokens=160, sampler=sampler, verbose=False)
            data = parse(out)
            if order == "relation":
                emit({"id": req["id"], "relation": str(data["relation"]), "topic": str(data.get("topic", "")),
                      "reason": str(data.get("reason", ""))})
            else:
                label = str(data["label"])
                if label not in ("on_task", "unsure", "off_task"):
                    raise ValueError("bad label %r" % label)
                emit({"id": req["id"], "label": label, "confidence": data.get("confidence"),
                      "reason": str(data.get("reason", ""))})
        except Exception as e:  # a bad generation is recorded as an error, which the harness counts as unsure
            emit({"id": req["id"], "error": "parse_error", "detail": "%s: %s" % (type(e).__name__, str(e)[:150])})


if __name__ == "__main__":
    main()
