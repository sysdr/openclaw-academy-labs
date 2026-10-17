#!/usr/bin/env bash
# demo: a 60-second walkthrough to show someone what the sandbox guarantees.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
load_env
PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
gateway_running || die "Gateway is not running. Run: make run"
CID="$(compose ps -q openclaw-gateway)"
step() { printf '\n== %s\n' "$1"; }

step "1. The agent lives in a container, and it is healthy"
compose ps openclaw-gateway
step "2. Its door opens only to this machine (127.0.0.1)"
docker port "$CID" 18789/tcp
step "3. Inside the box: not root, no Docker socket"
docker exec "$CID" sh -c 'echo "uid=$(id -u)"; [ -S /var/run/docker.sock ] && echo "docker.sock PRESENT" || echo "docker.sock absent"'
step "4. Ready to take traffic"
echo "GET /startupz -> $(http_code "http://127.0.0.1:$PORT/startupz")"
step "5. Shell commands are denied by policy"
oc approvals get --gateway --json 2>/dev/null \
  | python3 -c 'import json,sys; t=sys.stdin.read(); d=json.loads(t[t.find("{"):]); print("exec security:", [s["security"]["effective"] for s in d["effectivePolicy"]["scopes"]])'
step "6. First message"
oc agent --agent main --timeout 120 --json \
  --message "In one short sentence, say hello and name the machine you are running on." \
  2>/dev/null | python3 "$ROOT/src/l01_checks.py" text -
