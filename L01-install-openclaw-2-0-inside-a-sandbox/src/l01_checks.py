#!/usr/bin/env python3
"""Pure parsing helpers for verify.sh (standard library only).

Each subcommand reads a file (or stdin with "-") and prints one word:
PASS or FAIL, plus a short reason on stderr. verify.sh only looks at
the word, so the logic stays testable without Docker or OpenClaw.
"""
import ipaddress
import json
import re
import sys

NONCE_RE = re.compile(r"SANDBOX-OK-[A-Za-z0-9]{6,}")


def _read(path):
    if path == "-":
        return sys.stdin.read()
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _first_json(text):
    """Return the first JSON object in text (CLIs may print banners first)."""
    start = text.find("{")
    if start < 0:
        raise ValueError("no JSON object found")
    return json.JSONDecoder().raw_decode(text[start:])[0]


def inspect_summary(text):
    """Summarise `docker inspect <id>` output into the facts verify.sh checks."""
    data = json.loads(text)
    c = data[0] if isinstance(data, list) else data
    host = c.get("HostConfig") or {}
    state = c.get("State") or {}
    health = (state.get("Health") or {}).get("Status", "none")
    sec_opts = host.get("SecurityOpt") or []
    cap_drop = [x.upper() for x in (host.get("CapDrop") or [])]
    mounts = c.get("Mounts") or []
    sock = any("docker.sock" in (m.get("Source", "") + m.get("Destination", "")) for m in mounts)
    return {
        "running": bool(state.get("Running")),
        "healthy": health == "healthy",
        "no_new_privileges": any(o.replace("=", ":").startswith("no-new-privileges:true") or o == "no-new-privileges"
                                 for o in sec_opts),
        "cap_drop_all": "ALL" in cap_drop,
        "privileged": bool(host.get("Privileged")),
        "docker_sock_mounted": sock,
        "read_only_rootfs": bool(host.get("ReadonlyRootfs")),
    }


def ports_loopback_only(text):
    """`docker port <id> 18789/tcp` lines like 127.0.0.1:18789 or [::1]:18789."""
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if not lines:
        return False
    for ln in lines:
        host = ln.rsplit(":", 1)[0].strip("[]")
        try:
            if not ipaddress.ip_address(host).is_loopback:
                return False
        except ValueError:
            return False
    return True


def agent_reply_text(text):
    """Join payload texts from `openclaw agent --json`; None if the run failed."""
    obj = _first_json(text)
    if obj.get("ok") is False or obj.get("status") not in ("ok", None):
        return None
    result = obj.get("result") or obj
    payloads = result.get("payloads") or []
    texts = [p.get("text") or "" for p in payloads if isinstance(p, dict)]
    return "\n".join(t for t in texts if t) or None


def reply_has_nonce(text, nonce):
    reply = agent_reply_text(text)
    return bool(reply) and nonce in reply


def exec_policy_denied(text):
    """`openclaw approvals get --json`: every tools.exec scope is effective deny."""
    obj = _first_json(text)
    scopes = (obj.get("effectivePolicy") or {}).get("scopes") or []
    exec_scopes = [s for s in scopes if s.get("scopeLabel") == "tools.exec"]
    if not exec_scopes:
        return False
    return all((s.get("security") or {}).get("effective") == "deny" for s in exec_scopes)


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: l01_checks.py <cmd> <file|-> [arg]\n")
        return 2
    cmd, path = argv[1], argv[2]
    try:
        text = _read(path)
        if cmd == "text":
            print(agent_reply_text(text) or "")
            return 0
        if cmd == "inspect":
            for k, v in inspect_summary(text).items():
                print(f"{k}={'true' if v else 'false'}")
            return 0
        if cmd == "ports":
            ok = ports_loopback_only(text)
        elif cmd == "reply":
            ok = reply_has_nonce(text, argv[3])
        elif cmd == "policy":
            ok = exec_policy_denied(text)
        else:
            sys.stderr.write(f"unknown command {cmd}\n")
            return 2
    except (ValueError, json.JSONDecodeError, OSError, IndexError, KeyError, TypeError) as exc:
        sys.stderr.write(f"parse error: {exc}\n")
        ok = False
    print("PASS" if ok else "FAIL")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
