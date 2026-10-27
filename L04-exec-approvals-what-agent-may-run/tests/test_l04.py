"""Unit tests for L04 helpers (no OpenClaw needed) plus one live integration test."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))
import l04  # noqa: E402
import probe_model  # noqa: E402


def load(*parts):
    with open(os.path.join(ROOT, *parts), encoding="utf-8") as fh:
        return json.load(fh)


def snap(doc, effective):
    return {"file": doc, "effectivePolicy": {"scopes": [{"agentId": "main", "security": {"effective": effective}}]}}


class PolicyCheckTests(unittest.TestCase):
    def test_lesson_config_passes_every_check(self):
        desired = load("config", "exec-approvals.json")
        results = l04.policy_checks(snap(desired, "allowlist"), desired)
        self.assertTrue(all(ok for ok, _ in results), [label for ok, label in results if not ok])
        self.assertEqual(len(results), 8)

    def test_loose_config_fails_the_dangerous_checks(self):
        desired = load("config", "exec-approvals.json")
        results = dict((label.split(" (")[0], ok) for ok, label in
                       l04.policy_checks(snap(load("fixtures", "approvals-loose.json"), "full"), desired))
        self.assertFalse(results["defaults.security is deny"])
        self.assertFalse(results["askFallback is deny"])
        self.assertFalse(results["no interpreter allowlisted without argPattern"])
        self.assertFalse(results["effective security is allowlist"])

    def test_extra_entry_breaks_exact_match(self):
        desired = load("config", "exec-approvals.json")
        live = json.loads(json.dumps(desired))
        live["agents"]["main"]["allowlist"].append({"pattern": "/usr/bin/curl"})
        failed = [label for ok, label in l04.policy_checks(snap(live, "allowlist"), desired) if not ok]
        self.assertEqual(len(failed), 1)
        self.assertIn("allowlist matches config exactly", failed[0])

    def test_interpreter_with_argpattern_is_tolerated(self):
        doc = {"defaults": {"security": "deny"}, "agents": {"main": {"security": "allowlist", "ask": "on-miss",
               "autoAllowSkills": False, "allowlist": [{"pattern": "python3", "argPattern": "^safe\\.py$"}]}}}
        checks = dict((label, ok) for ok, label in l04.policy_checks(snap(doc, "allowlist"), doc))
        self.assertTrue(checks["no interpreter allowlisted without argPattern"])


class ClassifyTests(unittest.TestCase):
    def test_real_denial_texts_from_2026_10_7(self):
        self.assertEqual(l04.classify('{\n  "status": "error",\n  "tool": "exec",\n  "error": "exec denied: Headless runs cannot wait"}'), "deny")
        self.assertEqual(l04.classify("Exec denied (SYSTEM_RUN_DENIED: approval cannot safely bind this command): uptime > x"), "deny")
        self.assertEqual(l04.classify("03:12:56 up 12 min,  0 user,  load average: 0.56"), "allow")

    def test_classify_after_ignores_old_lines(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = os.path.join(tmp, "p.jsonl")
            with open(log, "w") as fh:
                fh.write(json.dumps({"command": "curl x", "result": "page body"}) + "\n")
                fh.write(json.dumps({"command": "curl x", "result": "exec denied: nope"}) + "\n")
            self.assertEqual(l04.classify_after(log, "curl x", 0), "deny")
            self.assertEqual(l04.classify_after(log, "curl x", 2), "missing")
            self.assertEqual(l04.classify_after(os.path.join(tmp, "none"), "curl x"), "missing")

    def test_cases_fill_in_canary(self):
        out = subprocess.run([sys.executable, os.path.join(ROOT, "src", "l04.py"), "cases",
                              os.path.join(ROOT, "fixtures", "cases.json"), "/tmp/c"], capture_output=True, text=True)
        rows = [line.split("\t") for line in out.stdout.strip().splitlines()]
        self.assertEqual(len(rows), 7)
        self.assertTrue(any(r[1] == "uptime && touch /tmp/c" and r[3] == "1" for r in rows))


class ProbeModelTests(unittest.TestCase):
    def test_run_directive_becomes_exec_call_then_record(self):
        req = {"messages": [{"role": "user", "content": "RUN: git push\n\nRuntime: agent=main"}],
               "tools": [{"function": {"name": "exec"}}]}
        reply, call, record = probe_model.decide(req, now_ms=42)
        self.assertIsNone(reply)
        self.assertEqual(json.loads(call["function"]["arguments"])["command"], "git push")
        follow = {"messages": req["messages"] + [{"role": "tool", "tool_call_id": "l04-x-42", "content": "exec denied"}]}
        _, call2, record = probe_model.decide(follow)
        self.assertIsNone(call2)
        self.assertEqual(record["command"], "git push")

    def test_no_exec_tool_means_no_call(self):
        reply, call, _ = probe_model.decide({"messages": [{"role": "user", "content": "RUN: ls"}], "tools": []})
        self.assertIsNone(call)
        self.assertIn("PROBE_IDLE", reply)


@unittest.skipUnless(shutil.which("openclaw") and os.environ.get("L04_LIVE") == "1",
                     "integration: needs openclaw on PATH, a running gateway, and L04_LIVE=1")
class LiveIntegrationTests(unittest.TestCase):
    def test_live_policy_matches_config(self):
        raw = subprocess.run(["openclaw", "approvals", "get", "--json"], capture_output=True, text=True, check=True).stdout
        results = l04.policy_checks(json.loads(raw), load("config", "exec-approvals.json"))
        self.assertTrue(all(ok for ok, _ in results), [label for ok, label in results if not ok])


if __name__ == "__main__":
    unittest.main()
