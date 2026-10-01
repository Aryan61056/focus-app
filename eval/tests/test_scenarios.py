import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
from focus_eval import scenarios  # noqa: E402


class ShippedScenarioTests(unittest.TestCase):
    def test_shipped_files_validate(self):
        items = scenarios.load_dir(os.path.join(HERE, "scenarios"))
        self.assertGreaterEqual(len(items), 60)

    def test_every_label_and_difficulty_present(self):
        items = scenarios.load_dir(os.path.join(HERE, "scenarios"))
        self.assertEqual({s.label for s in items}, set(scenarios.LABELS))
        self.assertEqual({s.difficulty for s in items}, set(scenarios.DIFFICULTIES))


class ValidationTests(unittest.TestCase):
    def _load(self, data):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "a.json"), "w") as fh:
                json.dump(data, fh)
            return scenarios.load_dir(d)

    def good(self, **kw):
        base = {"id": "a-1", "category": "c", "difficulty": "clear", "task": "t", "app": "x",
                "window_title": "w", "label": "on_task", "notes": "n"}
        base.update(kw)
        return base

    def test_accepts_minimal(self):
        self.assertEqual(len(self._load([self.good()])), 1)

    def test_rejects_bad_label(self):
        with self.assertRaises(scenarios.ScenarioError):
            self._load([self.good(label="maybe")])

    def test_rejects_duplicate_ids(self):
        with self.assertRaises(scenarios.ScenarioError):
            self._load([self.good(), self.good()])

    def test_rejects_unknown_field(self):
        with self.assertRaises(scenarios.ScenarioError):
            self._load([self.good(extra=1)])

    def test_rejects_unknown_project_key(self):
        with self.assertRaises(scenarios.ScenarioError):
            self._load([self.good(project={"nope": []})])


if __name__ == "__main__":
    unittest.main()
