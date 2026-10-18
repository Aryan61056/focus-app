"""Tests for tools/beta: report validation (privacy guard included), the inbox, the summary and the tester roster.
Run: python3 -m unittest discover -s tools/beta -p 'test_*.py'"""
from __future__ import annotations

import copy
import io
import json
import pathlib
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import feedback  # noqa: E402
import testers  # noqa: E402

SAMPLE = json.loads((HERE / "fixtures" / "sample-report.json").read_text())


def variant(**changes) -> dict:
    r = copy.deepcopy(SAMPLE)
    for path, value in changes.items():
        node = r
        keys = path.split("__")
        for k in keys[:-1]:
            node = node[int(k)] if k.isdigit() else node[k]
        last = keys[-1]
        if value is ...:
            del node[last]
        else:
            node[int(last) if last.isdigit() else last] = value
    return r


class Validation(unittest.TestCase):
    def test_sample_passes(self):
        self.assertEqual(feedback.validate(SAMPLE), [])

    def test_minimal_report_passes(self):
        r = {k: SAMPLE[k] for k in ("schema", "id", "created", "kind", "message", "app")}
        self.assertEqual(feedback.validate(r), [])

    def refused(self, r, needle):
        with self.assertRaises(feedback.Refused) as c:
            feedback.validate(r)
        self.assertIn(needle, str(c.exception))

    def test_refuses_wrong_schema(self):
        self.refused(variant(schema="focus-feedback/2"), "schema")

    def test_refuses_unknown_top_key(self):
        r = variant(); r["windowTitle"] = "Inbox"
        self.refused(r, "never writes")

    def test_refuses_path_anywhere_the_app_writes(self):
        self.refused(variant(crash__frames__0="focus-app /Users/sam/Applications/Focus.app"), "file path")
        self.refused(variant(system__model="/Users/sam"), "file path")

    def test_refuses_long_settings_value(self):
        self.refused(variant(settings__preset="Calc homework: integration by parts"), "longer")

    def test_refuses_unknown_event(self):
        self.refused(variant(events__0__kind="windowSeen"), "unknown")

    def test_refuses_text_in_event_value(self):
        self.refused(variant(events__3__value="youtube.com"), "not a number")

    def test_refuses_empty_or_huge_message(self):
        self.refused(variant(message="  "), "empty")
        self.refused(variant(message="x" * 4001), "longer")

    def test_refuses_bad_pulse_score(self):
        self.refused(variant(pulses__0__score=7), "1 to 5")

    def test_refuses_non_uuid(self):
        self.refused(variant(id="../../etc/passwd"), "UUID")

    def test_warns_about_secrets_in_message(self):
        w = feedback.validate(variant(message="it asked for password: hunter2 and card 4111 1111 1111 1111"))
        self.assertEqual(w, ["looks like a card number", "looks like a password"])


class Inbox(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.tmp.name)
        self.inbox = self.dir / "inbox"
        self.drop = self.dir / "drop"; self.drop.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, name, r):
        p = self.drop / name
        p.write_text(json.dumps(r) if not isinstance(r, str) else r)
        return p

    def test_ingest_files_dedupes_and_refuses(self):
        self.put("a.json", SAMPLE)
        self.put("b.json", variant(id="11111111-2222-4333-8444-555555555555", kind="wrongCall", message="Called my notes off task"))
        self.put("bad.json", variant(id="22222222-2222-4333-8444-555555555555", settings__preset="/Users/sam/x"))
        self.put("junk.json", "{not json")
        filed, dupes, refused = feedback.ingest([str(self.drop)], self.inbox, today="2026-10-18")
        self.assertEqual(len(filed), 2)
        self.assertEqual(sorted(p.rsplit("/", 1)[1] for p, _ in refused), ["bad.json", "junk.json"])
        filed, dupes, refused = feedback.ingest([str(self.drop / "a.json")], self.inbox)
        self.assertEqual((filed, dupes), ([], [SAMPLE["id"]]))
        t = feedback.read_triage(self.inbox)
        self.assertEqual(t[SAMPLE["id"]]["status"], "new")
        self.assertEqual(t[SAMPLE["id"]]["received"], "2026-10-18")

    def test_triage_by_prefix(self):
        self.put("a.json", SAMPLE)
        feedback.ingest([str(self.drop)], self.inbox)
        rid = feedback.set_status(self.inbox, "6f1c", "fixed", note="guarded tick", issue="#12")
        t = feedback.read_triage(self.inbox)[rid]
        self.assertEqual((t["status"], t["issue"], t["notes"][0]["text"]), ("fixed", "#12", "guarded tick"))
        with self.assertRaises(SystemExit):
            feedback.set_status(self.inbox, "6f1c", "shipped")

    def test_summary_and_pages(self):
        second = variant(id="11111111-2222-4333-8444-555555555555", kind="wrongCall", message="Notes flagged")
        # The same tester's journal again: shared events must count once.
        second["events"].append({"at": "2026-10-18T10:00:00Z", "kind": "sessionStart"})
        self.put("a.json", SAMPLE); self.put("b.json", second)
        feedback.ingest([str(self.drop)], self.inbox)
        s = feedback.summarize(feedback.reports(self.inbox), feedback.read_triage(self.inbox))
        self.assertEqual(s["reports"], 2)
        self.assertEqual(s["sessions"], 2)
        self.assertEqual(s["events"]["uncleanExit"], 1)
        self.assertEqual(s["unclean_per_100"], 50.0)
        self.assertEqual(s["back_found"], 100)
        self.assertEqual(s["pulse_weeks"], {"2026-W42": (4, 1)})
        self.assertEqual(s["wrong_call_share"], 50)
        self.assertEqual(list(s["crashes"]), ["EXC_BREAKPOINT SIGTRAP at focus-app SessionController.tick()"])
        md, pg = feedback.write_report(self.inbox, made="2026-10-18 12:00")
        text, page = md.read_text(), pg.read_text()
        self.assertIn("Unclean exits per 100 launches | 50.0", text)
        self.assertIn("`6f1c1d2e` bug", text)
        # The page is local and inert: no scripts and no outside addresses.
        self.assertNotIn("<script", page)
        self.assertNotRegex(page, r"https?://")
        self.assertIn("prefers-color-scheme:dark", page)

    def test_messages_are_escaped_in_the_page(self):
        self.put("a.json", variant(message="<img src=x onerror=alert(1)>"))
        feedback.ingest([str(self.drop)], self.inbox)
        _, pg = feedback.write_report(self.inbox)
        self.assertNotIn("<img", pg.read_text())

    def test_command_line_check_exit_codes(self):
        good = self.put("a.json", SAMPLE)
        bad = self.put("b.json", variant(kind="rant"))
        with redirect_stdout(io.StringIO()):
            self.assertEqual(feedback.main(["check", str(good)]), 0)
            self.assertEqual(feedback.main(["check", str(good), str(bad)]), 1)


class Roster(unittest.TestCase):
    def test_add_send_list_drop(self):
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "testers.csv"
            out = io.StringIO()
            with redirect_stdout(out):
                testers.main(["add", "Sam", "--mac", "M1 Pro"], path)
                testers.main(["add", "Ari"], path)
                with self.assertRaises(SystemExit):
                    testers.main(["add", "sam"], path)
                testers.main(["sent", "sam", "0.1.0-beta.1"], path)
                testers.main(["list"], path)
                testers.main(["drop", "Ari"], path)
            rows = testers.read(path)
            self.assertEqual([r["name"] for r in rows], ["Sam"])
            self.assertEqual(rows[0]["last_build"], "0.1.0-beta.1")
            self.assertEqual(oct(path.stat().st_mode & 0o777), "0o600")
            self.assertIn("0.1.0-beta.1", out.getvalue())


if __name__ == "__main__":
    unittest.main()
