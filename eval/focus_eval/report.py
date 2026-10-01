"""Markdown report for one run."""
from __future__ import annotations

from typing import List, Optional

from . import metrics

TARGET_PRECISION = 0.97
TARGET_RECALL = 0.85


def pct(x: Optional[float]) -> str:
    return "n/a" if x is None else "%.1f%%" % (100 * x)


def ci(pair) -> str:
    return "[%.0f-%.0f%%]" % (100 * pair[0], 100 * pair[1])


def render(results: List[dict], meta: dict, thresholds=(0.0, 0.5, 0.7, 0.8, 0.9)) -> str:
    h = metrics.headline(results)
    out = []
    out.append("# Eval run: %s" % meta["label"])
    out.append("")
    out.append("scenarios: %d | text mode: %s | rules: %s | stages: %s" % (
        len(results), meta["text_mode"], "on" if meta["use_rules"] else "off", metrics.stage_mix(results)))
    out.append("")
    out.append("## Headline (per moment, no confidence threshold)")
    out.append("")
    out.append("| Metric | Value | 95% CI | Target | Met |")
    out.append("|---|---|---|---|---|")
    ps, pl = h["precision_strict"], h["precision_lenient"]
    rc, ra = h["recall_clear"], h["recall_all"]
    out.append("| Off-task precision, strict (gold unsure counts as false nudge) | %s (%d of %d) | %s | >= 97%% | %s |" % (
        pct(ps), h["tp"], h["flagged"], ci(h["precision_strict_ci"]), "yes" if ps is not None and ps >= TARGET_PRECISION else "no"))
    out.append("| Off-task precision, lenient (only gold on_task counts) | %s | %s | >= 97%% | %s |" % (
        pct(pl), ci(h["precision_lenient_ci"]), "yes" if pl is not None and pl >= TARGET_PRECISION else "no"))
    out.append("| Recall, clear distractions | %s (of %d) | %s | >= 85%% | %s |" % (
        pct(rc), h["gold_off_task_clear"], ci(h["recall_clear_ci"]), "yes" if rc is not None and rc >= TARGET_RECALL else "no"))
    out.append("| Recall, all off-task | %s (of %d) | %s | n/a | |" % (pct(ra), h["gold_off_task"], ci(h["recall_all_ci"])))
    out.append("| Accuracy, 3-way | %s | | n/a | |" % pct(metrics.accuracy(results)))
    out.append("| False nudges on gold on_task | %s | | | |" % pct(h["false_nudge_rate_on_task"]))
    cal = metrics.calibration(results)
    out.append("| Calibration error (stated confidence, n=%d) | %s | | < 0.05 | %s |" % (
        cal["n"], "n/a" if cal["ece"] is None else "%.3f" % cal["ece"],
        "yes" if cal["ece"] is not None and cal["ece"] < 0.05 else "no"))
    lat = metrics.latency(results)
    if lat["n"]:
        out.append("| Model latency p50 / p95 | %.0f / %.0f ms | | text judge < 2000 ms | %s |" % (
            lat["p50_ms"], lat["p95_ms"], "yes" if lat["p95_ms"] < 2000 else "no"))
    out.append("")
    out.append("## Confusion (rows gold, columns predicted)")
    out.append("")
    out.append("| gold \\ pred | on_task | unsure | off_task |")
    out.append("|---|---|---|---|")
    conf = metrics.confusion(results)
    for g in metrics.LABELS:
        out.append("| %s | %d | %d | %d |" % (g, conf[g]["on_task"], conf[g]["unsure"], conf[g]["off_task"]))
    out.append("")
    out.append("## Confidence threshold sweep (a call counts as confirmed only above the threshold)")
    out.append("")
    out.append("| Threshold | Flagged | Precision strict | Precision lenient | Recall clear |")
    out.append("|---|---|---|---|---|")
    for row in metrics.threshold_sweep(results, thresholds):
        out.append("| %.0f | %d | %s | %s | %s |" % (
            100 * row["threshold"], row["flagged"], pct(row["precision_strict"]),
            pct(row["precision_lenient"]), pct(row["recall_clear"])))
    for key, title in (("category", "Per category"), ("difficulty", "Clear vs gray")):
        out.append("")
        out.append("## %s" % title)
        out.append("")
        out.append("| Group | n | Accuracy | Flagged off-task | False nudges | Missed off-task |")
        out.append("|---|---|---|---|---|---|")
        for name, g in metrics.by_group(results, key).items():
            out.append("| %s | %d | %s | %d | %d | %d |" % (
                name, g["n"], pct(g["accuracy"]), g["flagged"], g["false_nudges"], g["missed_off_task"]))
    errs = [r for r in results if r.get("error")]
    out.append("")
    out.append("## Refusals and errors: %d (counted as unsure)" % len(errs))
    for r in errs:
        out.append("- %s: %s" % (r["id"], r["error"]))
    out.append("")
    out.append("## False nudges (predicted off_task, gold is not)")
    out.append("")
    bad = [r for r in results if r["pred"] == "off_task" and r["gold"] != "off_task"]
    if not bad:
        out.append("none")
    for r in bad:
        out.append("- %s [gold %s, conf %s] %s -- %s" % (
            r["id"], r["gold"], "n/a" if r.get("confidence") is None else "%.0f" % (100 * r["confidence"]),
            r["title"], r.get("reason", "")))
    out.append("")
    out.append("## Missed off-task (gold off_task, predicted otherwise)")
    out.append("")
    miss = [r for r in results if r["gold"] == "off_task" and r["pred"] != "off_task"]
    if not miss:
        out.append("none")
    for r in miss:
        out.append("- %s [pred %s, conf %s] %s -- %s" % (
            r["id"], r["pred"], "n/a" if r.get("confidence") is None else "%.0f" % (100 * r["confidence"]),
            r["title"], r.get("reason", "")))
    out.append("")
    return "\n".join(out)
