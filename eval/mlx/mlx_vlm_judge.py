"""MLX vision-language judge helper: reads a screenshot PNG instead of window text.

  uv run --project eval python eval/mlx/mlx_vlm_judge.py <model-dir>

Request:  {"id", "instructions", "prompt", "order", "image": "<png path>"}
Response: same shape as mlx_judge.py. Loads weights from a local directory only.
The PNGs are synthetic renders from eval/swift/shotgen; no real screen is captured.
"""
import json
import os
import sys

os.environ.setdefault("HF_HUB_OFFLINE", "1")

from mlx_vlm import generate, load  # noqa: E402
from mlx_vlm.prompt_utils import apply_chat_template  # noqa: E402
from mlx_vlm.utils import load_config  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mlx_judge import FORMATS, emit, parse  # noqa: E402  (shared output formats and parser)


def main():
    path = sys.argv[1]
    model, processor = load(path)
    config = load_config(path)
    emit({"status": "available", "model": os.path.basename(path.rstrip("/"))})
    for line in sys.stdin:
        req = json.loads(line)
        order = req.get("order", "reason-first")
        text = (req["instructions"] + "\n\nThe attached image is a screenshot of the window.\n\n" + req["prompt"]
                + "\n\nReply with only one JSON object, no other text, in this shape:\n" + FORMATS[order])
        try:
            formatted = apply_chat_template(processor, config, text, num_images=1)
            result = generate(model, processor, formatted, [req["image"]], max_tokens=160, temperature=0.0, verbose=False)
            data = parse(result.text if hasattr(result, "text") else str(result))
            if order == "relation":
                emit({"id": req["id"], "relation": str(data["relation"]), "topic": str(data.get("topic", "")),
                      "reason": str(data.get("reason", ""))})
            else:
                label = str(data["label"])
                if label not in ("on_task", "unsure", "off_task"):
                    raise ValueError("bad label %r" % label)
                emit({"id": req["id"], "label": label, "confidence": data.get("confidence"),
                      "reason": str(data.get("reason", ""))})
        except Exception as e:
            emit({"id": req["id"], "error": "parse_error", "detail": "%s: %s" % (type(e).__name__, str(e)[:150])})


if __name__ == "__main__":
    main()
