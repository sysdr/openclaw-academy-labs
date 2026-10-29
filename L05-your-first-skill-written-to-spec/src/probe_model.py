#!/usr/bin/env python3
"""Skill probe: a scripted, OpenAI-compatible model for the L05 activation test.

It is not an LLM. It records every request OpenClaw sends (the system prompt,
tools and messages) and follows one skill mechanically, so the activation test
is deterministic and needs no API key:

  1. If the target skill is listed in <available_skills>, call skills_read
     (through OpenClaw's tool_call) for that exact name.
  2. When the skill body comes back, run the one command it names with exec.
  3. Format the reply the way the skill's spec says.

If the skill is not listed, it replies "PROBE no-skill <name>". A real model
makes step 1 by reading descriptions; verify.sh LIVE_MODEL=... checks that path.

Standard library only. Binds 127.0.0.1 only.
"""
import argparse
import json
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SKILL_TAG = re.compile(r"<skill>\s*<name>([^<]+)</name>\s*<description>([^<]*)</description>\s*<location>([^<]+)</location>", re.S)
UPTIME = re.compile(r"up\s+(?P<up>.+?),\s+\d+\s+users?,\s+load averages?:\s*(?P<l1>[\d.]+),?\s+(?P<l5>[\d.]+),?\s+(?P<l15>[\d.]+)")
UPTIME_NO_USERS = re.compile(r"up\s+(?P<up>.+?),\s+load averages?:\s*(?P<l1>[\d.]+),?\s+(?P<l5>[\d.]+),?\s+(?P<l15>[\d.]+)")


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(p.get("text", "") for p in content if isinstance(p, dict))
    return ""


def listed_skills(system_text):
    return {m.group(1).strip(): {"description": m.group(2).strip(), "location": m.group(3).strip()}
            for m in SKILL_TAG.finditer(system_text)}


RUN_RE = re.compile(r"Run `([^`]+)` with the `exec` tool")
PREFIX_RE = re.compile(r"`([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*-REPORT)\s")


def skill_contract(body_text):
    """Pull the one command and the reply prefix out of a skill body (JSON-escaped or not)."""
    text = body_text.replace("\\n", "\n").replace('\\"', '"')
    run, prefix = RUN_RE.search(text), PREFIX_RE.search(text)
    return (run.group(1) if run else None), (prefix.group(1) if prefix else "PROBE")


def format_uptime(raw):
    line = raw.strip().splitlines()[-1] if raw.strip() else ""
    m = UPTIME.search(line) or UPTIME_NO_USERS.search(line)
    if not m:
        return "UPTIME-REPORT error=unparsed uptime output"
    up = re.sub(r"\s+", " ", m.group("up")).strip()
    return f"UPTIME-REPORT up={up} load={m.group('l1')},{m.group('l5')},{m.group('l15')}"


def decide(body, skill):
    """Return (record, assistant_message) for one chat-completions request."""
    msgs = body.get("messages", [])
    system = "\n".join(text_of(m.get("content")) for m in msgs if m.get("role") in ("system", "developer"))
    # OpenClaw can append "runtime context" user messages; the turn starts at the last real request.
    is_ctx = lambda m: text_of(m.get("content")).startswith("OpenClaw runtime context")  # noqa: E731
    last_user = max((i for i, m in enumerate(msgs) if m.get("role") == "user" and not is_ctx(m)), default=-1)
    turn = msgs[last_user + 1:] if last_user >= 0 else []
    user_text = text_of(msgs[last_user].get("content")) if last_user >= 0 else ""
    skills = listed_skills(system)
    tool_results = [text_of(m.get("content")) for m in turn if m.get("role") == "tool"]
    calls = sum(len(m.get("tool_calls") or []) for m in turn if m.get("role") == "assistant")
    rec = {
        "ts": time.time(),
        "skill": skill,
        "skill_listed": skill in skills,
        "listed_entry": skills.get(skill),
        "listed_count": len(skills),
        "user_text": user_text[:1500],
        "step": calls,
    }
    if last_user < 0 or calls > 2 or (msgs and msgs[-1].get("role") == "user" and is_ctx(msgs[-1])):
        rec["action"] = "idle"  # background or unrecognised turn: never loop
        return rec, {"role": "assistant", "content": "PROBE idle"}
    if "PROBE: record-only" in user_text:
        rec["action"] = "record-only"
        return rec, {"role": "assistant", "content": "PROBE recorded"}
    if skill not in skills and calls == 0:
        rec["action"] = "no-skill"
        return rec, {"role": "assistant", "content": f"PROBE no-skill {skill}"}
    if calls == 0:
        rec["action"] = "skills_read"
        return rec, tool_call("tool_call", {"id": "skills_read", "args": {"name": skill}}, "c1")
    # The skill body (returned by skills_read) names the command and the reply prefix.
    body_text = next((t for t in tool_results if f"name: {skill}" in t), "")
    command, prefix = skill_contract(body_text)
    if calls == 1:
        rec["skill_body_received"] = bool(body_text) and command is not None
        rec["skill_body_head"] = (tool_results[-1] if tool_results else "")[:300]
        if not rec["skill_body_received"]:
            rec["action"] = "skill-body-missing"
            return rec, {"role": "assistant", "content": f"PROBE error=skill body for {skill} not received"}
        rec["action"] = "exec"
        rec["command"] = command
        return rec, tool_call("exec", {"title": f"{command} for {skill}", "command": command}, "c2")
    result = tool_results[-1] if tool_results else ""
    rec["exec_result_head"] = result[:300]
    if "denied" in result.lower():
        reply = f"{prefix} error=exec denied"
    elif command == "uptime":
        reply = format_uptime(result)
    else:
        first = next((ln.strip() for ln in result.splitlines() if ln.strip()), "")
        reply = f"{prefix} raw={first[:80]}"
    rec["action"] = "reply"
    rec["reply"] = reply
    return rec, {"role": "assistant", "content": reply}


def tool_call(name, args, call_id):
    return {"role": "assistant", "content": None, "tool_calls": [
        {"id": call_id, "type": "function", "function": {"name": name, "arguments": json.dumps(args)}}]}


def make_handler(log_path, skill):
    class Handler(BaseHTTPRequestHandler):
        def _json(self, code, obj):
            data = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path.rstrip("/").endswith("/models"):
                self._json(200, {"object": "list", "data": [{"id": "skill-probe", "object": "model"}]})
            elif self.path == "/health":
                self._json(200, {"ok": True})
            else:
                self._json(404, {"error": "not found"})

        def do_POST(self):
            length = int(self.headers.get("content-length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
            rec, msg = decide(body, skill)
            rec["system_prompt"] = "\n".join(text_of(m.get("content")) for m in body.get("messages", [])
                                             if m.get("role") in ("system", "developer"))
            with open(log_path, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(rec) + "\n")
            finish = "tool_calls" if msg.get("tool_calls") else "stop"
            if body.get("stream"):
                self.send_response(200)
                self.send_header("content-type", "text/event-stream")
                self.end_headers()
                delta = {"role": "assistant"}
                if msg.get("tool_calls"):
                    delta["tool_calls"] = [dict(tc, index=i) for i, tc in enumerate(msg["tool_calls"])]
                else:
                    delta["content"] = msg["content"]
                for d, fr in ((delta, None), ({}, finish)):
                    chunk = {"id": "probe", "object": "chat.completion.chunk", "created": int(time.time()),
                             "model": "skill-probe", "choices": [{"index": 0, "delta": d, "finish_reason": fr}]}
                    self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
                usage = {"id": "probe", "object": "chat.completion.chunk", "created": int(time.time()),
                         "model": "skill-probe", "choices": [],
                         "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}
                self.wfile.write(f"data: {json.dumps(usage)}\n\ndata: [DONE]\n\n".encode())
            else:
                self._json(200, {"id": "probe", "object": "chat.completion", "created": int(time.time()),
                                 "model": "skill-probe",
                                 "choices": [{"index": 0, "message": msg, "finish_reason": finish}],
                                 "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}})

        def log_message(self, *args):
            pass
    return Handler


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", type=int, default=18999)
    ap.add_argument("--log", required=True, help="JSONL file that records each request")
    ap.add_argument("--skill", default="uptime-report")
    a = ap.parse_args(argv)
    server = ThreadingHTTPServer(("127.0.0.1", a.port), make_handler(a.log, a.skill))
    print(f"skill probe on 127.0.0.1:{a.port} following {a.skill}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
