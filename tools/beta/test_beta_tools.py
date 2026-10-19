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
import release_text  # noqa: E402
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

    def test_calls_hold_only_a_call_and_how(self):
        self.refused(variant(calls__0__call="youtube"), "unknown")
        self.refused(variant(calls__0__by="Safari"), "unknown")
        r = variant(); r["calls"][0]["title"] = "Inbox"
        self.refused(r, "never writes")
        self.refused(variant(calls=[SAMPLE["calls"][0]] * 13), "short list")

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


class GitHubPull(unittest.TestCase):
    ISSUES = [
        {"number": 7, "body": "### What happened\n\nIt quit.\n\n[focus-feedback.json](https://github.com/user-attachments/files/123/focus-feedback-2026-10-18-6f1c1d2e.json)",
         "comments": [{"body": "and again https://github.com/Aryan61056/focus-app/files/456/second.json and a picture https://github.com/user-attachments/assets/9/x.png"}]},
        {"number": 8, "body": "no file, and a look-alike https://example.com/user-attachments/files/1/x.json", "comments": []},
    ]

    def test_attachments_are_json_files_on_github_only(self):
        self.assertEqual(feedback.attachments(self.ISSUES[0]), [
            "https://github.com/user-attachments/files/123/focus-feedback-2026-10-18-6f1c1d2e.json",
            "https://github.com/Aryan61056/focus-app/files/456/second.json"])
        self.assertEqual(feedback.attachments(self.ISSUES[1]), [])

    def test_pull_files_reports_with_their_issue_and_skips_known_ones(self):
        second = variant(id="11111111-2222-4333-8444-555555555555", kind="wrongCall", message="Notes flagged")
        files = {"123": json.dumps(SAMPLE).encode(), "456": json.dumps(second).encode()}
        fetched = []

        def fetch(url):
            fetched.append(url)
            return files[url.split("/files/")[1].split("/")[0]]
        with tempfile.TemporaryDirectory() as d:
            inbox = pathlib.Path(d) / "inbox"
            filed, dupes, refused, failed = feedback.pull("o/r", inbox, fetch_issues=lambda repo: self.ISSUES, fetch=fetch)
            self.assertEqual((len(filed), refused, failed), (2, [], []))
            t = feedback.read_triage(inbox)
            self.assertEqual(t[SAMPLE["id"]]["issue"], "#7")
            self.assertTrue(t[SAMPLE["id"]]["source"].endswith("6f1c1d2e.json"))
            # A second pull downloads nothing it already has.
            fetched.clear()
            filed, dupes, refused, failed = feedback.pull("o/r", inbox, fetch_issues=lambda repo: self.ISSUES, fetch=fetch)
            self.assertEqual((filed, fetched), ([], []))

    def test_pull_refuses_an_edited_file_and_reports_a_failed_download(self):
        issues = [{"number": 9, "body": "https://github.com/user-attachments/files/1/a.json https://github.com/user-attachments/files/2/b.json", "comments": []}]

        def fetch(url):
            if "/1/" in url:
                return json.dumps(variant(settings__preset="/Users/sam/x")).encode()
            raise OSError("404")
        with tempfile.TemporaryDirectory() as d:
            filed, dupes, refused, failed = feedback.pull("o/r", pathlib.Path(d), fetch_issues=lambda repo: issues, fetch=fetch)
            self.assertEqual(len(filed), 0)
            self.assertIn("file path", refused[0][1])
            self.assertEqual(failed[0][0], "https://github.com/user-attachments/files/2/b.json")

    def test_summary_says_how_wrong_calls_were_decided(self):
        rs = [variant(kind="wrongCall"), variant(id="11111111-2222-4333-8444-555555555555", kind="wrongCall", calls__0__by="words"),
              variant(id="22222222-2222-4333-8444-555555555555")]
        s = feedback.summarize(rs, {})
        self.assertEqual(dict(s["wrong_by"]), {"model": 1, "words": 1})


class ReleaseText(unittest.TestCase):
    M = {"name": "0.1.0-beta.2", "version": "0.1.0", "build": 2, "buildID": "20261019-abc", "expires": "2026-11-18", "sha256": "ab" * 32,
         "signing": "ad-hoc", "repo": "https://github.com/o/r", "tag": "v0.1.0-beta.2", "dmg": "Focus-0.1.0-beta.2.dmg",
         "notes": ["Post feedback on GitHub"], "known": ["The notch can lag after sleep"]}

    def test_origin_repo_forms(self):
        for remote in ["https://github.com/o/r.git", "https://github.com/o/r", "git@github.com:o/r.git", "ssh://git@github.com/o/r.git\n"]:
            self.assertEqual(release_text.origin_repo(remote), "https://github.com/o/r", remote)
        for remote in ["", "https://gitlab.com/o/r.git", "https://github.com/o", "https://github.com.evil.com/o/r"]:
            self.assertEqual(release_text.origin_repo(remote), "", remote)

    def test_github_text_has_the_steps_forms_and_checksum(self):
        body = release_text.github_body(self.M)
        for want in ["Focus-0.1.0-beta.2.dmg", "Open Anyway", "November 18, 2026", "Post feedback on GitHub", "The notch can lag after sleep",
                     "https://github.com/o/r/issues/new?template=beta-wrong-call.yml", "ab" * 32, "Issues are public"]:
            self.assertIn(want, body)
        # The claims CLAUDE.md bans until the privacy tests pass, and no em dashes in testers' copy.
        for banned in ["OS-enforced", "cannot reach the network", "0 bytes sent", "\u2014"]:
            self.assertNotIn(banned, body)
        signed = dict(self.M, signing="developer-id", known=[])
        self.assertNotIn("Open Anyway", release_text.github_body(signed))
        self.assertNotIn("Known issues", release_text.github_body(signed))

    def test_invite_points_at_the_release(self):
        text = release_text.invite(self.M)
        self.assertIn("https://github.com/o/r/releases/tag/v0.1.0-beta.2", text)
        self.assertIn("https://github.com/o/r/issues", text)
        local = release_text.invite(dict(self.M, repo=None))
        self.assertNotIn("github.com", local)
        self.assertIn("Open Focus-0.1.0-beta.2.dmg", local)


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
