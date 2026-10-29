#!/usr/bin/env python3
"""A small stand-in for the `openclaw` CLI, just enough for verify.sh.

MOCK_OC_HOME   folder holding workspace/skills/<name>/SKILL.md
MOCK_OC_MODE   pass  -> uptime is allowed, like the L04 allowlist
               fail  -> exec is denied, like a host whose allowlist lost uptime
L05_PROBE_PORT where the real probe model listens

`agent` imitates the parts of a real turn the test depends on: an
<available_skills> block with eligible skills only, the explicit-reference
note for $name, then a tool loop against the probe (skills_read, exec).
"""
import html
import json
import os
import re
import shutil
import sys
import urllib.request

HOME = os.environ["MOCK_OC_HOME"]
WS = os.path.join(HOME, "workspace")
MODE = os.environ.get("MOCK_OC_MODE", "pass")
PORT = int(os.environ.get("L05_PROBE_PORT", "18999"))
UPTIME_OUT = "10:01:02 up 3 days,  4:05,  2 users,  load average: 0.10, 0.20, 0.30"


def skills():
    root = os.path.join(WS, "skills")
    out = {}
    for d in sorted(os.listdir(root)) if os.path.isdir(root) else []:
        p = os.path.join(root, d, "SKILL.md")
        if not os.path.isfile(p):
            continue
        text = open(p, encoding="utf-8").read()
        name = re.search(r"^name:\s*(.+)$", text, re.M)
        desc = re.search(r"^description:\s*(.+)$", text, re.M)
        if not name or not desc:
            continue  # like OpenClaw: skipped, nothing reported
        bins = []
        meta = re.search(r"^metadata:\s*(.+)$", text, re.M)
        if meta:
            bins = json.loads(meta.group(1)).get("openclaw", {}).get("requires", {}).get("bins", [])
        missing = [b for b in bins if shutil.which(b) is None]
        out[name.group(1).strip()] = {"name": name.group(1).strip(), "description": desc.group(1).strip(),
                                      "filePath": p, "text": text, "missing": missing}
    return out


def info(name):
    s = skills().get(name)
    if not s:
        print(json.dumps({"ok": False, "error": f"skill not found: {name}"}))
        return 1
    ok = not s["missing"]
    print(json.dumps({"name": name, "description": s["description"], "source": "openclaw-workspace",
                      "filePath": s["filePath"], "eligible": ok, "modelVisible": ok,
                      "missing": {"bins": s["missing"], "anyBins": [], "env": [], "config": [], "os": []}}))
    return 0


def check():
    vis = [n for n, s in skills().items() if not s["missing"]]
    print(json.dumps({"agentId": "main", "workspaceDir": WS, "eligible": vis, "modelVisible": vis,
                      "missingRequirements": [n for n, s in skills().items() if s["missing"]]}))
    return 0


def post(messages):
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/chat/completions",
                                 data=json.dumps({"model": "skill-probe", "messages": messages, "stream": False}).encode(),
                                 headers={"content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)["choices"][0]["message"]


def agent(message):
    eligible = {n: s for n, s in skills().items() if not s["missing"]}
    block = "".join(f"  <skill>\n    <name>{html.escape(n)}</name>\n    <description>{html.escape(s['description'])}"
                    f"</description>\n    <location>{s['filePath']}</location>\n  </skill>\n" for n, s in eligible.items())
    system = f"## Skills\n<available_skills>\n{block}</available_skills>"
    refs = [n for n in eligible if f"${n}" in message]
    user = message if not refs else ("Use the following explicitly referenced skills for this request. "
                                     "Read each skill's SKILL.md before acting:\n" + "".join(f"- {n}\n" for n in refs)
                                     + f"\nUser request:\n{message}")
    msgs = [{"role": "system", "content": system}, {"role": "user", "content": user}]
    for _ in range(4):
        reply = post(msgs)
        if not reply.get("tool_calls"):
            break
        msgs.append(reply)
        for tc in reply["tool_calls"]:
            fn, args = tc["function"]["name"], json.loads(tc["function"]["arguments"])
            if fn == "tool_call" and args.get("id") == "skills_read":
                content = json.dumps({"result": {"content": eligible[args["args"]["name"]]["text"]}})
            elif fn == "exec":
                content = UPTIME_OUT if MODE == "pass" else "exec denied: allowlist miss"
            else:
                content = "unknown tool"
            msgs.append({"role": "tool", "tool_call_id": tc["id"], "content": content})
    text = reply.get("content") or ""
    print(json.dumps({"status": "ok", "result": {"payloads": [{"text": text}],
                                                 "meta": {"terminalReply": {"disposition": "visible", "text": text}}}}))
    return 0


def main(argv):
    if argv[:1] == ["health"]:
        print(json.dumps({"ok": True}))
        return 0
    if argv[:2] == ["skills", "info"]:
        return info(argv[2])
    if argv[:2] == ["skills", "check"]:
        return check()
    if argv[:1] == ["agent"]:
        return agent(argv[argv.index("--message") + 1])
    print(f"mock openclaw: unsupported: {' '.join(argv)}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
