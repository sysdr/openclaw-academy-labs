#!/usr/bin/env bash
# The Lesson 02 exposure audit: 10 checks, each against the RUNNING system.
# Evidence comes from three vantage points: the host (file modes, port
# publishing), Docker (what the container really runs with) and OpenClaw
# itself (its own audit and exec policy). Read-only: changes nothing.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need docker "install Docker: https://docs.docker.com/get-docker/"
need python3 "install Python 3.11+: https://www.python.org/downloads/"
load_env

EV="${AUDIT_EVIDENCE_DIR:-$(mktemp -d)}"
mkdir -p "$EV"
[ -n "${AUDIT_EVIDENCE_DIR:-}" ] || trap 'rm -rf "$EV"' EXIT

# --- collect evidence (a failure here leaves a file missing -> that check FAILs)
cid="$(compose ps -q "$SERVICE" 2>/dev/null || true)"
if [ -n "$cid" ]; then
  docker inspect "$cid" > "$EV/inspect.json" 2>/dev/null || rm -f "$EV/inspect.json"
  docker port "$cid" 18789 > "$EV/port.txt" 2>/dev/null || : > "$EV/port.txt"
  oc security audit --json > "$EV/oc-audit.json" 2>/dev/null || rm -f "$EV/oc-audit.json"
  oc approvals get --json > "$EV/approvals.json" 2>/dev/null || rm -f "$EV/approvals.json"
  oc config get gateway.auth.mode > "$EV/auth-mode.txt" 2>/dev/null || echo unset > "$EV/auth-mode.txt"
  oc config get security.audit.suppressions --json > "$EV/suppressions.json" 2>/dev/null \
    || echo '[]' > "$EV/suppressions.json"
  oc --version > "$EV/version.txt" 2>/dev/null || rm -f "$EV/version.txt"
else
  echo "Gateway container is not running. Fix: make run" >&2
fi
echo "${OPENCLAW_VERSION:-unset}" > "$EV/pin.txt"
{
  echo "env $(file_mode "$ENV_FILE")"
  echo "state $(file_mode "$STATE_DIR/openclaw")"
  echo "config $(file_mode "$STATE_DIR/openclaw/openclaw.json")"
  if grep -qxE '/?\.env' "$ROOT/.gitignore" 2>/dev/null; then echo "env_ignored yes"; else echo "env_ignored no"; fi
} > "$EV/modes.txt"

# --- run the 10 checks
n=0
run() {
  local name="$1" desc="$2" detail
  n=$((n + 1))
  if detail="$(python3 "$ROOT/src/l02_audit.py" "$name" "$EV" 2>&1)"; then
    printf '%2d. %-40s PASS  %s\n' "$n" "$desc" "$detail"; PASSES=$((PASSES + 1))
  else
    printf '%2d. %-40s FAIL  %s\n' "$n" "$desc" "$detail"; FAILS=$((FAILS + 1))
  fi
}

echo "OpenClaw exposure audit ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
run port-loopback      "Gateway port published on loopback only"
run gateway-auth       "Gateway requires a token or password"
run no-critical        "OpenClaw audit: 0 critical findings"
run no-warnings        "OpenClaw audit: 0 unexplained warnings"
run no-dangerous-flags "No dangerously* flags, even suppressed"
run exec-not-full      "Exec policy is not security=full"
run secrets-private    "Secrets and state are owner-only"
run least-privilege    "Container: non-root, no capabilities"
run no-escape-hatches  "Container: no host socket or namespaces"
run version-pinned     "Version pinned and past known RCE"
summary
