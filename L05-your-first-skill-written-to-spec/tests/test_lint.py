"""Unit tests for src/lint_skill.py, plus one integration test that runs only with OpenClaw."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "src"))
import lint_skill  # noqa: E402

with open(os.path.join(ROOT, "fixtures", "lint-cases.json"), encoding="utf-8") as _fh:
    CASES = json.load(_fh)


class LintCases(unittest.TestCase):
    def _lint(self, case):
        with tempfile.TemporaryDirectory() as tmp:
            d = os.path.join(tmp, case["dir"])
            os.makedirs(d)
            p = os.path.join(d, "SKILL.md")
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(case["text"])
            return lint_skill.lint(p)

    def test_each_fixture_fails_exactly_the_expected_rules(self):
        for case in CASES:
            with self.subTest(case["id"]):
                failed = sorted(r for r, ok, _ in self._lint(case) if not ok)
                self.assertEqual(failed, sorted(case["fail_rules"]))

    def test_lesson_skill_passes(self):
        res = lint_skill.lint(os.path.join(ROOT, "skills", "uptime-report", "SKILL.md"))
        self.assertTrue(all(ok for _, ok, _ in res), res)

    def test_wrong_filename_fails_r1(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = os.path.join(tmp, "skill.md")
            with open(p, "w", encoding="utf-8") as fh:
                fh.write("---\nname: x\ndescription: y\n---\nbody\n")
            self.assertEqual(lint_skill.lint(p)[0][:2], ("R1", False))

    def test_check_bins_reports_missing_binary(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = os.path.join(tmp, "l05-gated")
            os.makedirs(d)
            p = os.path.join(d, "SKILL.md")
            with open(p, "w", encoding="utf-8") as fh:
                fh.write('---\nname: l05-gated\ndescription: x.\n'
                         'metadata: { "openclaw": { "requires": { "bins": ["l05-no-such-binary"] } } }\n---\nbody\n')
            r7 = [x for x in lint_skill.lint(p, check_bins=True) if x[0] == "R7"][0]
            self.assertFalse(r7[1])
            self.assertIn("l05-no-such-binary", r7[2])


def gateway_ready():
    if not shutil.which("openclaw"):
        return False
    try:
        return subprocess.run(["openclaw", "health", "--json"], capture_output=True, timeout=30).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


@unittest.skipUnless(gateway_ready(), "OpenClaw gateway not available")
class Integration(unittest.TestCase):
    def test_openclaw_sees_the_installed_skill_as_eligible(self):
        out = subprocess.run(["openclaw", "skills", "info", "uptime-report", "--json"],
                             capture_output=True, text=True, timeout=60)
        if out.returncode != 0:
            self.skipTest("skill not installed yet (run make setup)")
        info = json.loads(out.stdout)
        self.assertTrue(info["eligible"])
        self.assertEqual(info["source"], "openclaw-workspace")


if __name__ == "__main__":
    unittest.main()
