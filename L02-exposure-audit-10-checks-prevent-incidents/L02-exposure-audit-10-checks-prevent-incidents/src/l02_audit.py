#!/usr/bin/env python3
"""Lesson 02 exposure audit: pure check functions.

audit.sh collects evidence (docker inspect, docker port, `openclaw security
audit --json`, `openclaw approvals get --json`, file modes) into a folder.
Each check below reads only that folder, so every check can be unit-tested
with fixtures and no OpenClaw or Docker installed.

Usage: python3 src/l02_audit.py <check-name> <evidence-dir>
Prints one detail line, exits 0 on PASS and 1 on FAIL.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Findings OpenClaw emits when the Gateway accepts unauthenticated callers.
NO_AUTH_IDS = {"gateway.loopback_no_auth", "gateway.bind_no_auth", "gateway.http.no_auth"}
DANGEROUS_ID = "config.insecure_or_dangerous_flags"
LOOPBACK_HOSTS = {"127.0.0.1", "::1", "[::1]"}
# CVE-2026-25253 (token theft leading to RCE) is fixed in 2026.1.29.
# https://osv.dev/vulnerability/CVE-2026-25253
MIN_PATCHED = "2026.1.29"


def _load(ev: Path, name: str):
    path = ev / name
    if not path.exists():
        raise FileNotFoundError(f"missing evidence: {name}")
    text = path.read_text(encoding="utf-8")
    if name.endswith(".json"):
        # CLIs may print banner lines before JSON; start at the first brace.
        start = min([i for i in (text.find("{"), text.find("[")) if i >= 0], default=-1)
        if start < 0:
            raise ValueError(f"no JSON in {name}")
        return json.loads(text[start:])
    return text


def _inspect(ev: Path) -> dict:
    data = _load(ev, "inspect.json")
    return data[0] if isinstance(data, list) else data


def _findings(ev: Path, key: str = "findings") -> list[dict]:
    return list(_load(ev, "oc-audit.json").get(key) or [])


def version_tuple(v: str) -> tuple[int, ...]:
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", v or "")
    if not m:
        raise ValueError(f"no version in {v!r}")
    return tuple(int(x) for x in m.groups())


# 1 -------------------------------------------------------------------------
def port_loopback_only(ev: Path):
    lines = [ln.strip() for ln in _load(ev, "port.txt").splitlines() if ln.strip()]
    if not lines:
        return False, "gateway port is not published (is the container running?)"
    hosts = []
    for ln in lines:  # "127.0.0.1:18789" or "[::1]:18789" or "0.0.0.0:18789"
        hosts.append(ln.rsplit(":", 1)[0])
    bad = [h for h in hosts if h not in LOOPBACK_HOSTS]
    if bad:
        return False, "published on " + ", ".join(sorted(set(bad))) + " (reachable from your network)"
    return True, "published on " + ", ".join(sorted(set(hosts)))


# 2 -------------------------------------------------------------------------
def gateway_auth_required(ev: Path):
    mode = _load(ev, "auth-mode.txt").strip().splitlines()
    mode = mode[-1].strip().strip('"') if mode else ""
    hits = sorted({f.get("checkId") for f in _findings(ev)} & NO_AUTH_IDS)
    if mode not in {"token", "password"}:
        return False, f"gateway.auth.mode is {mode or 'unset'}"
    if hits:
        return False, "audit reports " + ", ".join(hits)
    return True, f"gateway.auth.mode={mode}"


# 3 -------------------------------------------------------------------------
def no_critical(ev: Path):
    crit = [f.get("checkId") for f in _findings(ev) if f.get("severity") == "critical"]
    return (not crit), ("0 critical" if not crit else "critical: " + ", ".join(crit))


# 4 -------------------------------------------------------------------------
def no_warnings(ev: Path):
    warn = [f.get("checkId") for f in _findings(ev) if f.get("severity") == "warn"]
    if warn:
        return False, "warn: " + ", ".join(warn)
    raw = _load(ev, "oc-audit.json")
    suppressed = raw.get("suppressedFindings") or []
    # A suppression without a written reason is a hidden warning.
    sup_cfg = _load(ev, "suppressions.json") if (ev / "suppressions.json").exists() else []
    if not isinstance(sup_cfg, list):  # unset path returns an error envelope
        sup_cfg = []
    unexplained = [s.get("checkId") for s in sup_cfg if not str(s.get("reason", "")).strip()]
    if unexplained:
        return False, "suppression without reason: " + ", ".join(unexplained)
    return True, f"0 warnings ({len(suppressed)} suppressed with reasons)"


# 5 -------------------------------------------------------------------------
def no_dangerous_flags(ev: Path):
    active = [f for f in _findings(ev) if f.get("checkId") == DANGEROUS_ID]
    hidden = [f for f in _findings(ev, "suppressedFindings") if f.get("checkId") == DANGEROUS_ID]
    n = len(active) + len(hidden)
    if n:
        return False, f"{n} dangerous flag(s) enabled ({len(hidden)} suppressed)"
    return True, "no dangerously* flags, active or suppressed"


# 6 -------------------------------------------------------------------------
def exec_not_full(ev: Path):
    scopes = (_load(ev, "approvals.json").get("effectivePolicy") or {}).get("scopes") or []
    if not scopes:
        return False, "no effective exec policy reported"
    bad = []
    for s in scopes:
        sec = (s.get("security") or {}).get("effective")
        fb = (s.get("askFallback") or {}).get("effective")
        label = s.get("agentId") or s.get("scopeLabel") or "?"
        if sec == "full":
            bad.append(f"{label}: security=full")
        if fb != "deny":
            bad.append(f"{label}: askFallback={fb}")
    if bad:
        return False, "; ".join(bad)
    secs = sorted({(s.get("security") or {}).get("effective") for s in scopes})
    return True, "exec security=" + ",".join(secs) + ", askFallback=deny"


# 7 -------------------------------------------------------------------------
def secrets_private(ev: Path):
    """modes.txt lines: '<label> <octal-mode>' or '<label> missing'."""
    want = {"env": 0o600, "state": 0o700, "config": 0o600}
    got = {}
    for ln in _load(ev, "modes.txt").splitlines():
        parts = ln.split()
        if len(parts) == 2:
            got[parts[0]] = parts[1]
    bad = []
    for label, mode in want.items():
        val = got.get(label, "missing")
        if val == "missing":
            bad.append(f"{label} missing")
        elif int(val, 8) & 0o077:
            bad.append(f"{label} is {val} (want {oct(mode)[2:]})")
    if got.get("env_ignored") != "yes":
        bad.append(".env not in .gitignore")
    if bad:
        return False, "; ".join(bad)
    return True, ".env 600, state 700, openclaw.json 600, .env git-ignored"


# 8 -------------------------------------------------------------------------
def container_least_privilege(ev: Path):
    c = _inspect(ev)
    hc = c.get("HostConfig") or {}
    user = str((c.get("Config") or {}).get("User") or "")
    bad = []
    if user.split(":")[0] in {"", "0", "root"}:
        bad.append(f"runs as {user or 'root (no user set)'}")
    if "ALL" not in [x.upper() for x in (hc.get("CapDrop") or [])]:
        bad.append("capabilities not dropped (cap_drop ALL)")
    if hc.get("CapAdd"):
        bad.append("cap_add " + ",".join(hc["CapAdd"]))
    if not any(str(o).startswith("no-new-privileges") for o in (hc.get("SecurityOpt") or [])):
        bad.append("no-new-privileges missing")
    if bad:
        return False, "; ".join(bad)
    return True, f"user {user}, cap_drop ALL, no-new-privileges"


# 9 -------------------------------------------------------------------------
def no_escape_hatches(ev: Path):
    c = _inspect(ev)
    hc = c.get("HostConfig") or {}
    bad = []
    if hc.get("Privileged"):
        bad.append("privileged")
    for key in ("NetworkMode", "PidMode", "IpcMode"):
        if str(hc.get(key) or "") == "host":
            bad.append(f"{key}=host")
    for m in c.get("Mounts") or []:
        src = str(m.get("Source") or "")
        if src.endswith("docker.sock") or src.endswith("containerd.sock"):
            bad.append(f"mounts {src}")
        elif m.get("Type") == "bind" and src in {"/", "/home", "/Users", "/root", "/etc"}:
            bad.append(f"mounts host {src}")
    if bad:
        return False, "; ".join(bad)
    return True, "not privileged, no host namespaces, no runtime socket"


# 10 ------------------------------------------------------------------------
def version_pinned(ev: Path):
    c = _inspect(ev)
    image = str((c.get("Config") or {}).get("Image") or "")
    pin = _load(ev, "pin.txt").strip()
    running = _load(ev, "version.txt").strip()
    tag = image.rsplit(":", 1)[1] if ":" in image.rsplit("/", 1)[-1] else ""
    bad = []
    if tag in {"", "latest", "main"}:
        bad.append(f"image {image or '?'} is not pinned to a version tag")
    try:
        rv = version_tuple(running)
        if rv != version_tuple(pin):
            bad.append(f"running {'.'.join(map(str, rv))}, pinned {pin}")
        if rv < version_tuple(MIN_PATCHED):
            bad.append(f"older than {MIN_PATCHED} (CVE-2026-25253)")
    except ValueError as exc:
        bad.append(str(exc))
    if bad:
        return False, "; ".join(bad)
    return True, f"running {pin} = pin, >= {MIN_PATCHED}"


CHECKS = {
    "port-loopback": port_loopback_only,
    "gateway-auth": gateway_auth_required,
    "no-critical": no_critical,
    "no-warnings": no_warnings,
    "no-dangerous-flags": no_dangerous_flags,
    "exec-not-full": exec_not_full,
    "secrets-private": secrets_private,
    "least-privilege": container_least_privilege,
    "no-escape-hatches": no_escape_hatches,
    "version-pinned": version_pinned,
}


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] not in CHECKS:
        print("usage: l02_audit.py <" + "|".join(CHECKS) + "> <evidence-dir>", file=sys.stderr)
        return 2
    try:
        ok, detail = CHECKS[argv[1]](Path(argv[2]))
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
        ok, detail = False, str(exc)
    print(detail)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
