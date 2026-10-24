#!/usr/bin/env bash
# rotate-token.sh - assignment solution: rotate the Gateway token and prove the old one is dead.
# OpenClaw reads OPENCLAW_GATEWAY_TOKEN at process start, so rotation = new .env + restart.
# RESTART_CMD (optional): command that restarts your Gateway, e.g. "openclaw gateway restart".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "$ROOT/scripts/lib.sh"

load_token
OLD="${OPENCLAW_GATEWAY_TOKEN:-}"
[ -n "$OLD" ] || { say "FAIL no current token. Run: make setup"; exit 1; }
PORT="$(resolve_port)"
body='{"tool":"sessions_list","action":"json","args":{}}'

code_with() {  # code_with <token> -> HTTP status, token passed on stdin not argv
  curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST \
    -H 'Content-Type: application/json' -H "@-" -d "$body" \
    "http://127.0.0.1:$PORT/tools/invoke" <<< "Authorization: Bearer $1" || true
}

# 1. Write the new token next to the old one, then swap atomically.
if command -v openssl >/dev/null 2>&1; then NEW="$(openssl rand -hex 32)"
else NEW="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"; fi
tmp="$(mktemp "$ROOT/.env.XXXXXX")"
( umask 077
  grep -v '^OPENCLAW_GATEWAY_TOKEN=' "$ROOT/.env" > "$tmp" || true
  printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$NEW" >> "$tmp" )
mv "$tmp" "$ROOT/.env" && chmod 600 "$ROOT/.env"
pass "new token written to .env (old one still in memory for the test)"

# 2. Restart so the Gateway picks it up.
if [ -n "${RESTART_CMD:-}" ]; then
  bash -c "$RESTART_CMD" >/dev/null 2>&1 &
elif [ -t 0 ]; then
  read -r -p "Restart your Gateway now (Ctrl-C then: make run), then press Enter " _
fi
for _ in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "http://127.0.0.1:$PORT/health" || true)" = "200" ] && break
  sleep 1
done

# 3. Prove it.
c_old="$(code_with "$OLD")"; c_new="$(code_with "$NEW")"
if [ "$c_old" = "401" ]; then pass "old token rejected (401)"; else fail "old token rejected" "got $c_old"; fi
case "$c_new" in 200|400|403|404) pass "new token accepted ($c_new)" ;; *) fail "new token accepted" "got $c_new" ;; esac
unset OLD NEW
summary
[ "$FAIL_COUNT" -eq 0 ]
