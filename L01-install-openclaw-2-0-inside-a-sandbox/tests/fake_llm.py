#!/usr/bin/env python3
"""Offline OpenAI-compatible chat model for integration tests (stdlib only).

It echoes the SANDBOX-OK-<hex> token found in the newest user message, so
verify.sh can prove the reply is fresh. Supports stream=true (SSE) and false.
"""
import json
import os
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = re.compile(r"SANDBOX-OK-[A-Za-z0-9]+")
MODEL = os.environ.get("FAKE_LLM_MODEL", "fake-model")


def reply_for(req):
    """Return the token from the last user message, else a fixed marker."""
    for msg in reversed(req.get("messages") or []):
        if msg.get("role") != "user":
            continue
        content = msg.get("content")
        if isinstance(content, list):
            content = " ".join(p.get("text", "") for p in content if isinstance(p, dict))
        found = TOKEN.findall(content or "")
        if found:
            return found[-1]
    return "SANDBOX-OK"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("fake_llm " + (fmt % args) + "\n")

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self._json(200, {"object": "list", "data": [{"id": MODEL, "object": "model", "owned_by": "fake"}]})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            req = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._json(400, {"error": "bad json"})
            return
        text, now = reply_for(req), int(time.time())
        usage = {"prompt_tokens": 10, "completion_tokens": 2, "total_tokens": 12}
        if not req.get("stream"):
            self._json(200, {"id": "chatcmpl-1", "object": "chat.completion", "created": now, "model": MODEL,
                             "choices": [{"index": 0, "message": {"role": "assistant", "content": text},
                                          "finish_reason": "stop"}], "usage": usage})
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        base = {"id": "chatcmpl-1", "object": "chat.completion.chunk", "created": now, "model": MODEL}
        for delta, finish in (({"role": "assistant", "content": ""}, None), ({"content": text}, None), ({}, "stop")):
            chunk = dict(base, choices=[{"index": 0, "delta": delta, "finish_reason": finish}])
            if finish:
                chunk["usage"] = usage
            self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


if __name__ == "__main__":
    host = os.environ.get("FAKE_LLM_HOST", "127.0.0.1")
    port = int(os.environ.get("FAKE_LLM_PORT", "18800"))
    ThreadingHTTPServer((host, port), Handler).serve_forever()
