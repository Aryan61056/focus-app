import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from focus_eval import rules  # noqa: E402
from focus_eval.scenarios import Scenario  # noqa: E402


def sc(**kw):
    base = dict(id="x", category="c", difficulty="clear", task="t", app="Google Chrome",
                window_title="w", label="on_task", notes="n")
    base.update(kw)
    return Scenario(**base)


class SensitiveTests(unittest.TestCase):
    def test_password_manager(self):
        self.assertTrue(rules.is_sensitive(sc(app="1Password")))

    def test_private_window_title(self):
        self.assertTrue(rules.is_sensitive(sc(window_title="Start Page - Private Browsing")))

    def test_bank_subdomain(self):
        self.assertTrue(rules.is_sensitive(sc(url="https://secure.chase.com/web/auth")))

    def test_other_password_managers(self):
        for app in ("KeePassXC", "Proton Pass", "Enpass", "Passwords"):
            self.assertTrue(rules.is_sensitive(sc(app=app)), app)

    def test_sensitive_match_ignores_case(self):
        self.assertTrue(rules.is_sensitive(sc(app="KEEPASSXC")))

    def test_lookalike_domain_is_not_sensitive(self):
        self.assertFalse(rules.is_sensitive(sc(url="https://notchase.com/")))

    def test_ordinary_page(self):
        self.assertFalse(rules.is_sensitive(sc(url="https://example.com/")))


class Stage1Tests(unittest.TestCase):
    def test_linked_domain_with_path_prefix(self):
        p = {"linked_domains": ["github.com/acme/payments-service"]}
        self.assertEqual(rules.stage1(sc(url="https://github.com/acme/payments-service/issues/3", project=p))[0], "on_task")
        self.assertIsNone(rules.stage1(sc(url="https://github.com/acme/other-repo", project=p)))

    def test_domain_does_not_match_suffix_lookalike(self):
        p = {"always_allow_domains": ["linkedin.com"]}
        self.assertIsNone(rules.stage1(sc(url="https://notlinkedin.com/", project=p)))

    def test_deny_beats_allow(self):
        p = {"always_allow_apps": ["Steam"], "always_off_apps": ["Steam"]}
        self.assertEqual(rules.stage1(sc(app="Steam", project=p))[0], "off_task")

    def test_linked_path(self):
        p = {"linked_paths": ["~/Documents/Thesis/"]}
        self.assertEqual(rules.stage1(sc(document_path="~/Documents/Thesis/refs/a.pdf", project=p))[1], "linked_path")
        self.assertIsNone(rules.stage1(sc(document_path="~/Documents/Thesis-old/a.pdf", project=p)))

    def test_no_project_no_rule(self):
        self.assertIsNone(rules.stage1(sc()))


if __name__ == "__main__":
    unittest.main()


class NeverJudgedTests(unittest.TestCase):
    def test_list_matches_the_swift_source(self):
        import os, re
        swift = open(os.path.join(os.path.dirname(__file__), "..", "..", "mac", "Sources", "FocusJudge", "Rules.swift")).read()
        block = re.search(r"defaultNeverJudgedApps: \[String\] = \[(.*?)\]", swift, re.S).group(1)
        self.assertEqual(re.findall(r'"([^"]+)"', block), rules.DEFAULT_NEVER_JUDGED_APPS)

    def test_messaging_music_and_blank_tab_but_not_a_real_page_titled_new_tab(self):
        from focus_eval.scenarios import Scenario
        def sc(app, title, url=""):
            return Scenario(id="x", category="c", difficulty="gray", task="t", app=app, window_title=title, url=url, label="unsure", notes="n")
        self.assertTrue(rules.is_never_judged(sc("WhatsApp", "Family")))
        self.assertTrue(rules.is_never_judged(sc("Spotify", "Playlist")))
        self.assertTrue(rules.is_never_judged(sc("Google Chrome", "New Tab", "chrome://newtab/")))
        self.assertFalse(rules.is_never_judged(sc("Google Chrome", "New Tab", "https://example.com/new")))
        self.assertFalse(rules.is_never_judged(sc("Visual Studio Code", "main.py")))
