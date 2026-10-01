import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from focus_eval import metrics  # noqa: E402


def row(gold, pred, conf=None, difficulty="clear", stage="model"):
    return {"gold": gold, "pred": pred, "confidence": conf, "difficulty": difficulty,
            "category": "c", "stage": stage, "latency_ms": 10.0}


class HeadlineTests(unittest.TestCase):
    def test_precision_strict_counts_unsure_as_false_nudge(self):
        rs = [row("off_task", "off_task"), row("unsure", "off_task"), row("on_task", "off_task")]
        h = metrics.headline(rs)
        self.assertAlmostEqual(h["precision_strict"], 1 / 3)
        self.assertAlmostEqual(h["precision_lenient"], 2 / 3)

    def test_recall_splits_clear_and_gray(self):
        rs = [row("off_task", "off_task", difficulty="clear"),
              row("off_task", "unsure", difficulty="clear"),
              row("off_task", "unsure", difficulty="gray")]
        h = metrics.headline(rs)
        self.assertAlmostEqual(h["recall_clear"], 0.5)
        self.assertAlmostEqual(h["recall_all"], 1 / 3)

    def test_threshold_removes_low_confidence_calls(self):
        rs = [row("off_task", "off_task", 0.9), row("on_task", "off_task", 0.4)]
        self.assertAlmostEqual(metrics.headline(rs, 0.0)["precision_strict"], 0.5)
        self.assertAlmostEqual(metrics.headline(rs, 0.5)["precision_strict"], 1.0)

    def test_no_flags_gives_none_precision(self):
        h = metrics.headline([row("on_task", "on_task")])
        self.assertIsNone(h["precision_strict"])

    def test_false_nudge_rate_only_over_gold_on_task(self):
        rs = [row("on_task", "off_task"), row("on_task", "on_task"), row("unsure", "off_task")]
        self.assertAlmostEqual(metrics.headline(rs)["false_nudge_rate_on_task"], 0.5)


class WilsonTests(unittest.TestCase):
    def test_known_value(self):
        lo, hi = metrics.wilson(19, 20)
        self.assertAlmostEqual(lo, 0.764, places=2)
        self.assertAlmostEqual(hi, 0.991, places=2)

    def test_empty(self):
        self.assertEqual(metrics.wilson(0, 0), (0.0, 1.0))

    def test_all_correct_interval_is_wide_for_small_n(self):
        lo, _ = metrics.wilson(20, 20)
        self.assertLess(lo, 0.85)  # 20 of 20 cannot certify a 97% target


class CalibrationTests(unittest.TestCase):
    def test_perfectly_calibrated(self):
        rs = [row("on_task", "on_task", 1.0), row("on_task", "on_task", 1.0)]
        self.assertAlmostEqual(metrics.calibration(rs)["ece"], 0.0)

    def test_overconfident(self):
        rs = [row("on_task", "on_task", 0.9), row("on_task", "off_task", 0.9)]
        self.assertAlmostEqual(metrics.calibration(rs)["ece"], 0.4)

    def test_missing_confidence(self):
        self.assertIsNone(metrics.calibration([row("on_task", "on_task", None)])["ece"])


class ConfusionTests(unittest.TestCase):
    def test_counts(self):
        rs = [row("on_task", "off_task"), row("on_task", "on_task")]
        c = metrics.confusion(rs)
        self.assertEqual(c["on_task"]["off_task"], 1)
        self.assertEqual(c["on_task"]["on_task"], 1)


if __name__ == "__main__":
    unittest.main()
