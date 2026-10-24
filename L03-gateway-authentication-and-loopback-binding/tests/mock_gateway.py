#!/usr/bin/env python3
"""Tiny stand-in for the OpenClaw Gateway HTTP surface used by verify.sh.

Implements only what Lesson 03 checks:
  GET  /health        -> 200 {"ok":true,"status":"live"}   (unauthenticated, as documented)
  POST /tools/invoke  -> 401 without a valid Bearer token, else 200 {"ok":true,"result":{}}

Passing state:  --host 127.0.0.1 --token "$OPENCLAW_GATEWAY_TOKEN"
Failing state:  --host 0.0.0.0 --accept-any   (exposed and unauthenticated)
"""
from __future__ import annotations

import argparse
import hmac
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def make_handler(token: str, accept_any: bool):
    class Handler(BaseHTTPRequestHandler):
        server_version = "mock-openclaw-gateway/0.1"

        def log_message(self, *_):  # keep test output quiet, never log headers
            pass

        def _send(self, code: int, body: dict) -> None:
            raw = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self):
            if self.path in ("/health", "/healthz"):
                self._send(200, {"ok": True, "status": "live"})
            else:
                self._send(404, {"ok": False})

        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            self.rfile.read(length)
            if self.path != "/tools/invoke":
                self._send(404, {"ok": False})
                return
            auth = self.headers.get("Authorization", "")
            presented = auth[7:] if auth.startswith("Bearer ") else ""
            if accept_any or (token and hmac.compare_digest(presented, token)):
                self._send(200, {"ok": True, "result": {}})
            else:
                self._send(401, {"ok": False, "error": {"type": "unauthorized"}})

    return Handler


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=18789)
    ap.add_argument("--token", default=os.environ.get("OPENCLAW_GATEWAY_TOKEN", ""))
    ap.add_argument("--accept-any", action="store_true")
    args = ap.parse_args()
    srv = ThreadingHTTPServer((args.host, args.port), make_handler(args.token, args.accept_any))
    print(f"mock gateway listening on {args.host}:{args.port}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
