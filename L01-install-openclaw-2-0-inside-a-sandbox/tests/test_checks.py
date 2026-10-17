"""Unit tests for src/l01_checks.py. Run: python3 -m unittest discover -s tests"""
import json
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))
import l01_checks as c  # noqa: E402

with open(os.path.join(ROOT, "fixtures", "cases.json"), encoding="utf-8") as fh:
    CASES = json.load(fh)


def dumps(key):
    return json.dumps(CASES[key])


class InspectSummary(unittest.TestCase):
    def test_hardened_container(self):
        s = c.inspect_summary(dumps("inspect_safe"))
        self.assertEqual(s, {"running": True, "healthy": True, "no_new_privileges": True,
                             "cap_drop_all": True, "privileged": False, "docker_sock_mounted": False,
                             "read_only_rootfs": False})

    def test_unsafe_container_is_flagged(self):
        s = c.inspect_summary(dumps("inspect_unsafe"))
        self.assertFalse(s["no_new_privileges"])
        self.assertFalse(s["cap_drop_all"])
        self.assertTrue(s["docker_sock_mounted"])

    def test_missing_health_is_not_healthy(self):
        data = CASES["inspect_safe"][0].copy()
        data["State"] = {"Running": True}
        self.assertFalse(c.inspect_summary(json.dumps([data]))["healthy"])


class Ports(unittest.TestCase):
    def test_loopback_v4_and_v6(self):
        self.assertTrue(c.ports_loopback_only("127.0.0.1:18789\n[::1]:18789\n"))

    def test_all_interfaces_fail(self):
        self.assertFalse(c.ports_loopback_only(CASES["ports_all"]))

    def test_one_public_binding_fails_the_set(self):
        self.assertFalse(c.ports_loopback_only("127.0.0.1:18789\n0.0.0.0:18789\n"))

    def test_nothing_published_fails(self):
        self.assertFalse(c.ports_loopback_only(""))


class AgentReply(unittest.TestCase):
    def test_reply_contains_nonce(self):
        self.assertTrue(c.reply_has_nonce(dumps("agent_ok"), "SANDBOX-OK-1a2b3c4d"))

    def test_stale_nonce_rejected(self):
        self.assertFalse(c.reply_has_nonce(dumps("agent_ok"), "SANDBOX-OK-ffffffff"))

    def test_error_envelope_rejected(self):
        self.assertIsNone(c.agent_reply_text(dumps("agent_error")))

    def test_banner_before_json_is_tolerated(self):
        text = "[openclaw] note: something\n" + dumps("agent_ok")
        self.assertEqual(c.agent_reply_text(text), "SANDBOX-OK-1a2b3c4d")


class ExecPolicy(unittest.TestCase):
    def test_deny(self):
        self.assertTrue(c.exec_policy_denied(dumps("approvals_deny")))

    def test_full_is_not_deny(self):
        self.assertFalse(c.exec_policy_denied(dumps("approvals_full")))

    def test_no_scopes_fails_closed(self):
        self.assertFalse(c.exec_policy_denied('{"effectivePolicy": {"scopes": []}}'))


class Cli(unittest.TestCase):
    def test_bad_input_prints_fail_not_traceback(self):
        import io
        from contextlib import redirect_stdout, redirect_stderr
        path = os.path.join(ROOT, "fixtures", "missing.json")
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = c.main(["l01_checks.py", "policy", path])
        self.assertEqual((rc, out.getvalue().strip()), (0, "FAIL"))


if __name__ == "__main__":
    unittest.main()
