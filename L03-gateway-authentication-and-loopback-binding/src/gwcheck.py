#!/usr/bin/env python3
"""Helpers for Lesson 03 verify.sh. Standard library only (Python 3.11+).

Subcommands (all print one value per line, never a secret):
  get <config> <dotted.key>   print a config value as JSON (or "null")
  literal-token <config>      print "yes" if gateway.auth.token is a literal string
  token-ok                    exit 0 if $OPENCLAW_GATEWAY_TOKEN looks strong
  listeners <port>            print local addresses listening on TCP <port>
  local-ips                   print non-loopback IPv4 addresses of this host
  is-loopback <addr>          exit 0 if addr is a loopback address
  is-wildcard <addr>          exit 0 if addr is 0.0.0.0, ::, or *
"""
from __future__ import annotations

import ipaddress
import json
import os
import re
import shutil
import socket
import subprocess
import sys

PLACEHOLDERS = ("replace", "changeme", "change-me", "your-token", "example", "secret", "xxxx")


# ---------- JSON5 (the subset OpenClaw configs use) ----------
def json5_to_json(text: str) -> str:
    """Strip comments, quote bare keys, convert single quotes, drop trailing commas."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in "\"'":
            quote, j, buf = c, i + 1, []
            while j < n and text[j] != quote:
                if text[j] == "\\" and j + 1 < n:
                    buf.append(text[j:j + 2])
                    j += 2
                    continue
                buf.append(text[j])
                j += 1
            body = "".join(buf)
            if quote == "'":
                body = body.replace('"', '\\"').replace("\\'", "'")
            out.append('"' + body + '"')
            i = j + 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
        elif (c.isalpha() or c in "_$") and _last_sig(out) in "{,":
            m = re.match(r"[A-Za-z_$][\w$]*", text[i:])
            ident = m.group(0)
            rest = text[i + len(ident):].lstrip()
            out.append(f'"{ident}"' if rest.startswith(":") else ident)
            i += len(ident)
        else:
            out.append(c)
            i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def _last_sig(out: list[str]) -> str:
    for chunk in reversed(out):
        stripped = chunk.strip()
        if stripped:
            return stripped[-1]
    return "{"


def load_config(path: str) -> dict:
    with open(os.path.expanduser(path), encoding="utf-8") as fh:
        text = fh.read()
    data = json.loads(json5_to_json(text))
    return data if isinstance(data, dict) else {}


def get_key(cfg: dict, dotted: str):
    cur = cfg
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def has_literal_token(cfg: dict) -> bool:
    tok = get_key(cfg, "gateway.auth.token")
    if tok is None or isinstance(tok, dict):  # absent, or a SecretRef object
        return False
    if isinstance(tok, str) and re.fullmatch(r"\$\{[A-Z0-9_]+\}", tok.strip()):
        return False  # env substitution, not a literal
    return True


def token_ok(tok: str | None) -> bool:
    if not tok or len(tok) < 32:
        return False
    low = tok.lower()
    return not any(p in low for p in PLACEHOLDERS) and len(set(tok)) >= 8


# ---------- network ----------
def is_loopback(addr: str) -> bool:
    addr = addr.strip().strip("[]").split("%")[0]
    try:
        ip = ipaddress.ip_address(addr)
    except ValueError:
        return addr == "localhost"
    if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return ip.is_loopback


def _split_addr(local: str) -> str:
    local = local.strip()
    if local.startswith("["):
        return local[1:local.index("]")]
    return local.rsplit(":", 1)[0] or "*"


def _run(cmd: list[str]) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def listeners(port: int) -> tuple[str, list[str]]:
    """Return (tool_used, [addresses]) for TCP listeners on port."""
    if shutil.which("ss"):
        out = _run(["ss", "-Hltn", f"sport = :{port}"])
        addrs = [_split_addr(line.split()[3]) for line in out.splitlines() if len(line.split()) >= 4]
        return "ss", addrs
    if shutil.which("lsof"):
        out = _run(["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-Fn"])
        addrs = sorted({_split_addr(l[1:]) for l in out.splitlines() if l.startswith("n")})
        return "lsof", addrs
    if shutil.which("netstat"):
        out = _run(["netstat", "-an"])
        addrs = []
        for line in out.splitlines():
            parts = line.split()
            if len(parts) >= 4 and "LISTEN" in line and parts[0].startswith("tcp"):
                local = parts[3]
                sep = "." if re.search(r"\.\d+$", local) and local.count(":") == 0 else ":"
                host, _, p = local.rpartition(sep)
                if p == str(port):
                    addrs.append(host or "*")
        return "netstat", addrs
    return "proc", _proc_listeners(port)


def _proc_listeners(port: int) -> list[str]:
    addrs = []
    for fname, v6 in (("/proc/net/tcp", False), ("/proc/net/tcp6", True)):
        try:
            rows = open(fname, encoding="ascii").read().splitlines()[1:]
        except OSError:
            continue
        for row in rows:
            cols = row.split()
            if len(cols) < 4 or cols[3] != "0A":  # 0A = LISTEN
                continue
            hexip, hexport = cols[1].split(":")
            if int(hexport, 16) != port:
                continue
            raw = bytes.fromhex(hexip)
            if v6:
                raw = b"".join(raw[i:i + 4][::-1] for i in range(0, 16, 4))
                addrs.append(str(ipaddress.IPv6Address(raw)))
            else:
                addrs.append(str(ipaddress.IPv4Address(raw[::-1])))
    return addrs


def is_wildcard(addr: str) -> bool:
    return addr.strip("[]") in ("*", "0.0.0.0", "::", "::0", "")


def local_ips() -> list[str]:
    found: set[str] = set()
    for cmd in (["ip", "-o", "-4", "addr", "show"], ["ifconfig"]):
        if shutil.which(cmd[0]):
            found.update(re.findall(r"inet (?:addr:)?(\d+\.\d+\.\d+\.\d+)", _run(cmd)))
    if shutil.which("hostname") and sys.platform.startswith("linux"):
        found.update(re.findall(r"\d+\.\d+\.\d+\.\d+", _run(["hostname", "-I"])))
    try:  # UDP "connect" picks the outbound interface; sends no packets
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        found.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    return sorted(ip for ip in found if not is_loopback(ip))


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    cmd, args = argv[0], argv[1:]
    try:
        if cmd == "get":
            print(json.dumps(get_key(load_config(args[0]), args[1])))
        elif cmd == "literal-token":
            print("yes" if has_literal_token(load_config(args[0])) else "no")
        elif cmd == "token-ok":
            return 0 if token_ok(os.environ.get("OPENCLAW_GATEWAY_TOKEN")) else 1
        elif cmd == "listeners":
            tool, addrs = listeners(int(args[0]))
            print(f"#tool={tool}")
            print("\n".join(addrs))
        elif cmd == "local-ips":
            print("\n".join(local_ips()))
        elif cmd == "is-loopback":
            return 0 if is_loopback(args[0]) else 1
        elif cmd == "is-wildcard":
            return 0 if is_wildcard(args[0]) else 1
        else:
            print(f"unknown subcommand: {cmd}", file=sys.stderr)
            return 2
    except (OSError, ValueError, IndexError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
