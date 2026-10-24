"""Integration test against a real OpenClaw Gateway. Skipped when OpenClaw is absent.

Run `make run` in another terminal first, then `make test`.
"""
import os
import shutil
import subprocess
import unittest
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = int(os.environ.get("OPENCLAW_GATEWAY_PORT", "18789"))


def gateway_up() -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2) as r:
            return r.status == 200
    except (urllib.error.URLError, OSError):
        return False


@unittest.skipUnless(shutil.which("openclaw"), "openclaw CLI not installed")
@unittest.skipUnless(gateway_up(), "no Gateway answering on 127.0.0.1 (run: make run)")
class LiveGateway(unittest.TestCase):
    def test_unauthenticated_invoke_is_rejected(self):
        req = urllib.request.Request(
            f"http://127.0.0.1:{PORT}/tools/invoke",
            data=b'{"tool":"sessions_list","action":"json","args":{}}',
            headers={"Content-Type": "application/json"}, method="POST")
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req, timeout=5)
        self.assertEqual(ctx.exception.code, 401)

    def test_verify_script_passes(self):
        proc = subprocess.run(["bash", os.path.join(ROOT, "scripts", "verify.sh")],
                              capture_output=True, text=True, timeout=120)
        self.assertEqual(proc.returncode, 0, proc.stdout)


if __name__ == "__main__":
    unittest.main()
