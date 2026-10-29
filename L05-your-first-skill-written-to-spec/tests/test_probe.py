"""Unit tests for the scripted probe model (no network, no OpenClaw)."""
import json
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))
import probe_model as pm  # noqa: E402

with open(os.path.join(ROOT, "skills", "uptime-report", "SKILL.md"), encoding="utf-8") as _fh:
    SKILL_BODY = _fh.read()
LISTED = ("<available_skills>\n  <skill>\n    <name>uptime-report</name>\n"
          "    <description>Report uptime.</description>\n"
          "    <location>~/.openclaw/workspace/skills/uptime-report/SKILL.md</location>\n  </skill>\n</available_skills>")


def body(system, *turn):
    return {"messages": [{"role": "system", "content": system},
                         {"role": "user", "content": "how long has this machine been up?"}, *turn]}


def call(name, cid):
    return {"role": "assistant", "content": None,
            "tool_calls": [{"id": cid, "type": "function", "function": {"name": name, "arguments": "{}"}}]}


class FormatUptime(unittest.TestCase):
    def test_linux(self):
        self.assertEqual(pm.format_uptime(" 10:01:02 up 3 days,  4:05,  2 users,  load average: 0.10, 0.20, 0.30"),
                         "UPTIME-REPORT up=3 days, 4:05 load=0.10,0.20,0.30")

    def test_linux_zero_users(self):
        self.assertEqual(pm.format_uptime("06:55:22 up 6 min,  0 user,  load average: 0.72, 0.69, 0.33"),
                         "UPTIME-REPORT up=6 min load=0.72,0.69,0.33")

    def test_macos(self):
        self.assertEqual(pm.format_uptime("10:01  up 3 days,  4:05, 2 users, load averages: 1.23 1.45 1.67"),
                         "UPTIME-REPORT up=3 days, 4:05 load=1.23,1.45,1.67")

    def test_garbage(self):
        self.assertIn("error=", pm.format_uptime("nope"))


class Decide(unittest.TestCase):
    def test_unlisted_skill_is_not_used(self):
        rec, msg = pm.decide(body("no skills here"), "uptime-report")
        self.assertEqual((rec["action"], msg["content"]), ("no-skill", "PROBE no-skill uptime-report"))

    def test_full_sequence(self):
        rec, msg = pm.decide(body(LISTED), "uptime-report")
        self.assertEqual(rec["action"], "skills_read")
        self.assertEqual(json.loads(msg["tool_calls"][0]["function"]["arguments"]),
                         {"id": "skills_read", "args": {"name": "uptime-report"}})
        t1 = [call("tool_call", "c1"), {"role": "tool", "tool_call_id": "c1", "content": json.dumps({"content": SKILL_BODY})}]
        rec, msg = pm.decide(body(LISTED, *t1), "uptime-report")
        self.assertEqual((rec["action"], rec["command"]), ("exec", "uptime"))
        t2 = t1 + [call("exec", "c2"), {"role": "tool", "tool_call_id": "c2",
                                         "content": "06:55:22 up 6 min,  0 user,  load average: 0.72, 0.69, 0.33"}]
        rec, msg = pm.decide(body(LISTED, *t2), "uptime-report")
        self.assertEqual(msg["content"], "UPTIME-REPORT up=6 min load=0.72,0.69,0.33")

    def test_denied_exec_is_reported_not_hidden(self):
        t = [call("tool_call", "c1"), {"role": "tool", "content": SKILL_BODY},
             call("exec", "c2"), {"role": "tool", "content": "exec denied: allowlist miss"}]
        _, msg = pm.decide(body(LISTED, *t), "uptime-report")
        self.assertEqual(msg["content"], "UPTIME-REPORT error=exec denied")

    def test_runtime_context_only_turn_goes_idle(self):
        b = body(LISTED)
        b["messages"].append({"role": "user", "content": "OpenClaw runtime context:\nConversation data"})
        rec, _ = pm.decide(b, "uptime-report")
        self.assertEqual(rec["action"], "idle")

    def test_contract_from_escaped_json(self):
        self.assertEqual(pm.skill_contract(json.dumps(SKILL_BODY)), ("uptime", "UPTIME-REPORT"))


if __name__ == "__main__":
    unittest.main()
