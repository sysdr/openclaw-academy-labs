"""End-to-end: run the real scripts/verify.sh against tests/mock_gateway.py.

Passing state:  mock on 127.0.0.1 with token auth + good config -> exit 0, "10/10 PASS".
Failing state:  mock on 0.0.0.0 accepting anyone + bad config   -> exit 1, exposure checks FAIL.
"""
import os
import secrets
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERIFY = os.path.join(ROOT, "scripts", "verify.sh")
MOCK = os.path.join(ROOT, "tests", "mock_gateway.py")


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for(port: int, timeout: float = 5.0) -> None:
    end = time.time() + timeout
    while time.time() < end:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.3):
                return
        except OSError:
            time.sleep(0.1)
    raise RuntimeError("mock gateway did not start")


class VerifyAgainstMock(unittest.TestCase):
    def run_case(self, mock_args, config, token):
        port = free_port()
        mock = subprocess.Popen([sys.executable, MOCK, "--port", str(port), *mock_args],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            wait_for(port)
            with tempfile.TemporaryDirectory() as reports:
                env = dict(os.environ,
                           OPENCLAW_CONFIG_PATH=os.path.join(ROOT, "fixtures", config),
                           OPENCLAW_GATEWAY_PORT=str(port),
                           OPENCLAW_GATEWAY_TOKEN=token,
                           VERIFY_REPORT_DIR=reports,
                           GW_MODE="native")
                proc = subprocess.run(["bash", VERIFY], env=env, capture_output=True,
                                      text=True, timeout=120)
                report_files = os.listdir(reports)
            return proc, report_files
        finally:
            mock.terminate()
            mock.wait(timeout=5)

    def test_passing_state(self):
        token = secrets.token_hex(32)
        proc, reports = self.run_case(["--host", "127.0.0.1", "--token", token], "good.json5", token)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn("10/10 PASS", proc.stdout)
        self.assertNotIn(token, proc.stdout)  # the secret never reaches output
        self.assertEqual(len(reports), 1)
        self.assertTrue(reports[0].startswith("verify-"))

    def test_failing_state(self):
        proc, _ = self.run_case(["--host", "0.0.0.0", "--accept-any"], "bad.json5", "short")
        self.assertEqual(proc.returncode, 1, proc.stdout)
        self.assertNotIn("10/10 PASS", proc.stdout)
        for check in ("01 ", "03 ", "04 ", "06 ", "09 "):
            line = next(l for l in proc.stdout.splitlines() if l.startswith(check))
            self.assertIn("FAIL", line, line)


if __name__ == "__main__":
    unittest.main()
