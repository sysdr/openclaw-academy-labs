"""Unit tests for src/gwcheck.py. No OpenClaw needed."""
import os
import socket
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))
import gwcheck  # noqa: E402

FIX = os.path.join(ROOT, "fixtures")


class Json5(unittest.TestCase):
    def test_good_fixture_parses(self):
        cfg = gwcheck.load_config(os.path.join(FIX, "good.json5"))
        self.assertEqual(gwcheck.get_key(cfg, "gateway.bind"), "loopback")
        self.assertEqual(gwcheck.get_key(cfg, "gateway.auth.mode"), "token")
        self.assertEqual(gwcheck.get_key(cfg, "gateway.auth.rateLimit.lockoutMs"), 300000)

    def test_single_quotes_comments_trailing_commas(self):
        text = "{ a: 'x', /* c */ b: [1, 2,], // tail\n url: \"http://h:1/p\", }"
        self.assertEqual(
            gwcheck.json.loads(gwcheck.json5_to_json(text)),
            {"a": "x", "b": [1, 2], "url": "http://h:1/p"},
        )

    def test_string_with_colon_and_comma_is_untouched(self):
        text = '{ note: "a, b: c" }'
        self.assertEqual(gwcheck.json.loads(gwcheck.json5_to_json(text)), {"note": "a, b: c"})


class Token(unittest.TestCase):
    def test_literal_token_detection(self):
        bad = gwcheck.load_config(os.path.join(FIX, "bad.json5"))
        good = gwcheck.load_config(os.path.join(FIX, "good.json5"))
        self.assertTrue(gwcheck.has_literal_token(bad))
        self.assertFalse(gwcheck.has_literal_token(good))
        env_ref = {"gateway": {"auth": {"token": "${OPENCLAW_GATEWAY_TOKEN}"}}}
        self.assertFalse(gwcheck.has_literal_token(env_ref))
        secret_ref = {"gateway": {"auth": {"token": {"source": "env", "id": "X"}}}}
        self.assertFalse(gwcheck.has_literal_token(secret_ref))

    def test_token_strength(self):
        self.assertTrue(gwcheck.token_ok("4c1e9a07d2b85f36" * 4))
        self.assertFalse(gwcheck.token_ok(None))
        self.assertFalse(gwcheck.token_ok("short"))
        self.assertFalse(gwcheck.token_ok("replace-me-" + "a1b2c3d4" * 4))
        self.assertFalse(gwcheck.token_ok("a" * 64))


class Network(unittest.TestCase):
    def test_loopback_classification(self):
        for addr in ("127.0.0.1", "127.8.9.1", "::1", "[::1]", "::ffff:127.0.0.1", "localhost"):
            self.assertTrue(gwcheck.is_loopback(addr), addr)
        for addr in ("0.0.0.0", "*", "::", "192.168.1.20", "10.0.0.5"):
            self.assertFalse(gwcheck.is_loopback(addr), addr)

    def test_wildcard_classification(self):
        for addr in ("*", "0.0.0.0", "::", "[::]"):
            self.assertTrue(gwcheck.is_wildcard(addr), addr)
        self.assertFalse(gwcheck.is_wildcard("127.0.0.1"))

    def test_split_addr(self):
        self.assertEqual(gwcheck._split_addr("127.0.0.1:18789"), "127.0.0.1")
        self.assertEqual(gwcheck._split_addr("[::1]:18789"), "::1")
        self.assertEqual(gwcheck._split_addr("*:18789"), "*")

    @unittest.skipUnless(os.path.exists("/proc/net/tcp"), "Linux /proc fallback only")
    def test_proc_fallback_sees_a_real_listener(self):
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        s.listen()
        port = s.getsockname()[1]
        try:
            self.assertIn("127.0.0.1", gwcheck._proc_listeners(port))
        finally:
            s.close()

    def test_local_ips_excludes_loopback(self):
        self.assertFalse(any(gwcheck.is_loopback(ip) for ip in gwcheck.local_ips()))


if __name__ == "__main__":
    unittest.main()
