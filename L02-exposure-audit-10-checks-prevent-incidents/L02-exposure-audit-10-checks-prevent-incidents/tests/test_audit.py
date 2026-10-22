"""Unit tests for src/l02_audit.py. No Docker or OpenClaw needed."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
import l02_audit as A  # noqa: E402

CASES = json.loads((ROOT / "fixtures" / "cases.json").read_text())


def evidence(case: str, **override) -> Path:
    d = Path(tempfile.mkdtemp())
    files = dict(CASES[case], **override)
    for name, text in files.items():
        if text is not None:
            (d / name).write_text(text)
    return d


class EveryCheck(unittest.TestCase):
    def test_good_case_passes_all_ten(self):
        ev = evidence("good")
        for name, fn in A.CHECKS.items():
            ok, detail = fn(ev)
            self.assertTrue(ok, f"{name}: {detail}")

    def test_bad_case_fails_all_ten(self):
        ev = evidence("bad")
        for name, fn in A.CHECKS.items():
            ok, detail = fn(ev)
            self.assertFalse(ok, f"{name} should fail: {detail}")

    def test_exactly_ten_checks(self):
        self.assertEqual(len(A.CHECKS), 10)


class EdgeCases(unittest.TestCase):
    def test_ipv6_loopback_is_fine(self):
        ok, _ = A.port_loopback_only(evidence("good", **{"port.txt": "127.0.0.1:18789\n[::1]:18789\n"}))
        self.assertTrue(ok)

    def test_one_wildcard_line_fails(self):
        ok, detail = A.port_loopback_only(evidence("good", **{"port.txt": "127.0.0.1:18789\n0.0.0.0:18789\n"}))
        self.assertFalse(ok)
        self.assertIn("0.0.0.0", detail)

    def test_unpublished_port_fails(self):
        self.assertFalse(A.port_loopback_only(evidence("good", **{"port.txt": ""}))[0])

    def test_suppressed_dangerous_flag_still_fails(self):
        audit = json.loads(CASES["good"]["oc-audit.json"])
        audit["suppressedFindings"] = [{"checkId": A.DANGEROUS_ID, "severity": "warn"}]
        ok, detail = A.no_dangerous_flags(evidence("good", **{"oc-audit.json": json.dumps(audit)}))
        self.assertFalse(ok)
        self.assertIn("1 suppressed", detail)

    def test_suppression_without_reason_fails(self):
        sup = json.dumps([{"checkId": "gateway.trusted_proxies_missing", "reason": " "}])
        self.assertFalse(A.no_warnings(evidence("good", **{"suppressions.json": sup}))[0])

    def test_suppression_with_reason_passes(self):
        sup = json.dumps([{"checkId": "gateway.trusted_proxies_missing", "reason": "no reverse proxy"}])
        self.assertTrue(A.no_warnings(evidence("good", **{"suppressions.json": sup}))[0])

    def test_cli_banner_before_json_is_ignored(self):
        text = "OpenClaw 2026.10.5 (1b58cb9)\n" + CASES["good"]["oc-audit.json"]
        self.assertTrue(A.no_critical(evidence("good", **{"oc-audit.json": text}))[0])

    def test_missing_evidence_fails_cleanly(self):
        ev = evidence("good", **{"inspect.json": None})
        self.assertEqual(A.main(["x", "least-privilege", str(ev)]), 1)

    def test_default_exec_policy_is_flagged(self):
        ok, detail = A.exec_not_full(evidence("bad"))
        self.assertFalse(ok)
        self.assertIn("security=full", detail)

    def test_root_user_flagged(self):
        insp = json.loads(CASES["good"]["inspect.json"])
        insp[0]["Config"]["User"] = "0:0"
        self.assertFalse(A.container_least_privilege(evidence("good", **{"inspect.json": json.dumps(insp)}))[0])

    def test_version_mismatch_flagged(self):
        ok, detail = A.version_pinned(evidence("good", **{"version.txt": "OpenClaw 2026.10.4 (383c124)"}))
        self.assertFalse(ok)
        self.assertIn("pinned 2026.10.5", detail)

    def test_version_ordering(self):
        self.assertLess(A.version_tuple("2026.1.24"), A.version_tuple(A.MIN_PATCHED))
        self.assertGreater(A.version_tuple("2026.10.5"), A.version_tuple("2026.9.33"))


if __name__ == "__main__":
    unittest.main()
