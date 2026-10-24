#!/usr/bin/env bash
# demo.sh - the 60-second show-and-tell. Needs `make run` going in another terminal.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

load_token
PORT="$(resolve_port)"
LAN="$(python3 "$GWCHECK" local-ips | head -n 1)"
body='{"tool":"sessions_list","action":"json","args":{}}'
step() { printf '\n> %s\n' "$1"; }

step "1. From this machine, the Gateway answers"
curl -s --max-time 3 "http://127.0.0.1:$PORT/health" || true; echo

step "2. Through the LAN address ${LAN:-(none)}, nothing is listening"
if [ -n "$LAN" ]; then
  curl -s -o /dev/null -w 'http=%{http_code}\n' --connect-timeout 2 "http://$LAN:$PORT/health" || true
fi

step "3. No token: rejected"
curl -s -o /dev/null -w 'http=%{http_code}\n' -X POST -H 'Content-Type: application/json' \
  -d "$body" "http://127.0.0.1:$PORT/tools/invoke" || true

step "4. With the token from .env: accepted"
curl -s -o /dev/null -w 'http=%{http_code}\n' -X POST -H 'Content-Type: application/json' \
  -H "@-" -d "$body" "http://127.0.0.1:$PORT/tools/invoke" \
  <<< "Authorization: Bearer ${OPENCLAW_GATEWAY_TOKEN:-}" || true

step "5. The proof"
bash "$ROOT/scripts/verify.sh" | tail -n 2
