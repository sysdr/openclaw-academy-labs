#!/usr/bin/env python3
"""L04 exec probe: a scripted, OpenAI-compatible model on 127.0.0.1.

It never "thinks". When the user message contains a line "RUN: <command>",
it asks OpenClaw's real exec tool to run exactly that command. When OpenClaw
returns the tool result, the probe appends {command, result} to a JSONL log.
That log is the evidence verify.sh reads: the text OpenClaw itself produced
after applying your exec approvals, independent of any model's judgment.

Standard library only. Binds to loopback only. No auth, no secrets.
"""
import json
import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RUN_RE = re.compile(r"RUN:[ \t]*([^\n]+)")
LOG_PATH = os.environ.get("L04_PROBE_LOG", ".state/probe-results.jsonl")
_pending = {}  # normalized tool_call_id -> command
_lock = threading.Lock()


def text_of(message):
    content = message.get("content")
    if isinstance(content, list):
        return " ".join(p.get("text", "") for p in content if isinstance(p, dict))
    return content or ""


def norm(call_id):
    """OpenClaw may rewrite tool-call ids (2026.10.7 drops '_'), so compare letters and digits only."""
    return re.sub(r"[^A-Za-z0-9]", "", call_id or "")


def extract_command(messages):
    """Return the RUN: command from the newest user message, or None."""
    for message in reversed(messages):
        if message.get("role") == "user":
            match = RUN_RE.search(text_of(message))
            return match.group(1).strip() if match else None
    return None


def decide(request, now_ms=None):
    """Pure decision function: returns (reply_text, tool_call, record)."""
    messages = request.get("messages", [])
    tools = {t.get("function", {}).get("name") for t in request.get("tools", [])}
    if messages and messages[-1].get("role") == "tool":
        call_id = messages[-1].get("tool_call_id", "")
        with _lock:
            command = _pending.pop(norm(call_id), None)
        result = text_of(messages[-1])
        record = {"ts": int(time.time()), "call_id": call_id, "command": command, "result": result}
        return "PROBE_DONE", None, record
    command = extract_command(messages)
    if command and "exec" in tools:
        call_id = "l04x%d" % (now_ms or int(time.time() * 1000))
        with _lock:
            _pending[norm(call_id)] = command
        args = json.dumps({"title": "L04 probe", "command": command})
        call = {"id": call_id, "type": "function", "function": {"name": "exec", "arguments": args}}
        return None, call, None
    return "PROBE_IDLE: send 'RUN: <command>'", None, None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _json(self, obj):
        data = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._json({"object": "list", "data": [{"id": "exec-probe", "object": "model"}]})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        request = json.loads(self.rfile.read(length) or b"{}")
        reply, call, record = decide(request)
        if record:
            os.makedirs(os.path.dirname(LOG_PATH) or ".", exist_ok=True)
            with open(LOG_PATH, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(record) + "\n")
        base = {"id": "probe", "created": int(time.time()), "model": "exec-probe"}
        if not request.get("stream"):
            msg = {"role": "assistant", "content": reply}
            if call:
                msg = {"role": "assistant", "content": None, "tool_calls": [call]}
            finish = "tool_calls" if call else "stop"
            self._json(dict(base, object="chat.completion",
                            choices=[{"index": 0, "message": msg, "finish_reason": finish}]))
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()

        def chunk(delta, finish=None):
            obj = dict(base, object="chat.completion.chunk",
                       choices=[{"index": 0, "delta": delta, "finish_reason": finish}])
            self.wfile.write(b"data: " + json.dumps(obj).encode() + b"\n\n")

        if call:
            chunk({"role": "assistant", "tool_calls": [dict(call, index=0)]})
            chunk({}, "tool_calls")
        else:
            chunk({"role": "assistant", "content": reply})
            chunk({}, "stop")
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18999
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print("probe listening on 127.0.0.1:%d, log %s" % (port, LOG_PATH), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
