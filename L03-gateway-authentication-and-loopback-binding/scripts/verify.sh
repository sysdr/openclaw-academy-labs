#!/usr/bin/env bash
# verify.sh - PROOF for Lesson 03: "Gateway reachable only from your machine".
# Ten checks: two locks (where it listens, who it lets in) tested from the outside.
# Env: OPENCLAW_CONFIG_PATH, OPENCLAW_GATEWAY_PORT, OPENCLAW_GATEWAY_TOKEN (or .env),
#      GW_MODE=native|docker, GW_CONTAINER (docker mode), VERIFY_REPORT_DIR.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

GW_MODE="${GW_MODE:-native}"
REPORT_DIR="${VERIFY_REPORT_DIR:-$ROOT/reports}"

# --- prerequisites (not counted in the proof) ---
if ! python_ok; then say "FAIL prerequisite: python3 >= 3.11 (install it, then rerun)"; exit 2; fi
if ! command -v curl >/dev/null 2>&1; then say "FAIL prerequisite: curl (install curl, then rerun)"; exit 2; fi
if [ ! -f "$CONFIG_PATH" ]; then say "FAIL prerequisite: config not found at $CONFIG_PATH (run: make setup)"; exit 2; fi

load_token
PORT="$(resolve_port)"
BASE="http://127.0.0.1:$PORT"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/verify-$(date -u +%Y%m%dT%H%M%SZ).txt"

http_code() {
  # http_code <url> [curl args...] -> prints status code, "000" if no connection
  local url="$1"; shift
  curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 5 "$@" "$url" || true
}

run_checks() {
  say "Lesson 03 verify  config=$CONFIG_PATH  port=$PORT  mode=$GW_MODE"

  # 1. Where it listens (config)
  local bind
  bind="$(python3 "$GWCHECK" get "$CONFIG_PATH" gateway.bind)"
  if [ "$GW_MODE" = "docker" ]; then
    local maps bad
    maps="$(docker port "${GW_CONTAINER:-openclaw-gateway}" 2>/dev/null | awk -F' -> ' '{print $2}')"
    bad="$(printf '%s\n' "$maps" | grep -Ev '^(127\.|\[::1\])' | grep -v '^$' || true)"
    if [ -n "$maps" ] && [ -z "$bad" ]; then pass "01 docker publishes gateway to loopback only"
    else fail "01 docker publishes gateway to loopback only" "mappings: ${maps:-none}"; fi
  elif [ "$bind" = '"loopback"' ]; then pass "01 gateway.bind is \"loopback\""
  else fail "01 gateway.bind is \"loopback\"" "found $bind"; fi

  # 2. Who it lets in (config)
  local mode
  mode="$(python3 "$GWCHECK" get "$CONFIG_PATH" gateway.auth.mode)"
  if [ "$mode" = '"token"' ]; then pass "02 gateway.auth.mode is \"token\""
  else fail "02 gateway.auth.mode is \"token\"" "found $mode"; fi

  # 3. Secret stays out of the config file
  if [ "$(python3 "$GWCHECK" literal-token "$CONFIG_PATH")" = "no" ]; then
    pass "03 no literal token in config file"
  else fail "03 no literal token in config file" "move it to OPENCLAW_GATEWAY_TOKEN"; fi

  # 4. Token is present and strong (value never printed)
  if python3 "$GWCHECK" token-ok; then pass "04 token set, >=32 chars, not a placeholder"
  else fail "04 token set, >=32 chars, not a placeholder" "run: make setup"; fi

  # 5 + 6. Listener addresses, observed from the OS
  local out tool addrs non_lo wild
  out="$(python3 "$GWCHECK" listeners "$PORT")"
  tool="$(printf '%s\n' "$out" | sed -n 's/^#tool=//p')"
  addrs="$(printf '%s\n' "$out" | grep -v '^#' | grep -v '^$' || true)"
  non_lo=""; wild=""
  while IFS= read -r a; do
    [ -z "$a" ] && continue
    python3 "$GWCHECK" is-loopback "$a" || non_lo="$non_lo $a"
    if python3 "$GWCHECK" is-wildcard "$a"; then wild="$wild $a"; fi
  done <<< "$addrs"
  if [ -z "$addrs" ]; then fail "05 listener on :$PORT is loopback-only ($tool)" "nothing listening; run: make run"
  elif [ -z "$non_lo" ]; then pass "05 listener on :$PORT is loopback-only ($tool)"
  else fail "05 listener on :$PORT is loopback-only ($tool)" "also on:$non_lo"; fi
  if [ -n "$addrs" ] && [ -z "$wild" ]; then pass "06 no wildcard listener (0.0.0.0, ::, *)"
  else fail "06 no wildcard listener (0.0.0.0, ::, *)" "${wild:- nothing listening}"; fi

  # 7. Reachable from your machine
  local code
  code="$(http_code "$BASE/health")"
  if [ "$code" = "200" ]; then pass "07 GET /health on 127.0.0.1 returns 200"
  else fail "07 GET /health on 127.0.0.1 returns 200" "got $code"; fi

  # 8. Not reachable through any other address this machine owns
  local ips reached=""
  ips="$(python3 "$GWCHECK" local-ips)"
  for ip in $ips; do
    code="$(http_code "http://$ip:$PORT/health")"
    [ "$code" != "000" ] && reached="$reached $ip"
  done
  if [ -z "$ips" ]; then pass "08 no non-loopback interface to reach (none found)"
  elif [ -z "$reached" ]; then pass "08 refused on LAN address(es): $(echo "$ips" | tr '\n' ' ' | sed 's/ $//')"
  else fail "08 refused on LAN address(es)" "answered on:$reached"; fi

  # 9. Wrong or missing credentials are rejected
  local body='{"tool":"sessions_list","action":"json","args":{}}'
  local c_none c_bad
  c_none="$(http_code "$BASE/tools/invoke" -X POST -H 'Content-Type: application/json' -d "$body")"
  c_bad="$(http_code "$BASE/tools/invoke" -X POST -H 'Content-Type: application/json' \
            -H 'Authorization: Bearer not-the-token-0000000000000000' -d "$body")"
  if [ "$c_none" = "401" ] && [ "$c_bad" = "401" ]; then pass "09 no token and wrong token both get 401"
  else fail "09 no token and wrong token both get 401" "no-token=$c_none wrong=$c_bad"; fi

  # 10. The right token gets in (any non-auth status means auth passed)
  local c_ok
  c_ok="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 10 \
           -X POST -H 'Content-Type: application/json' \
           -H "@-" -d "$body" "$BASE/tools/invoke" <<< "Authorization: Bearer ${OPENCLAW_GATEWAY_TOKEN:-}" || true)"
  case "$c_ok" in
    200|400|403|404) pass "10 correct token is accepted (HTTP $c_ok)" ;;
    *) fail "10 correct token is accepted" "got $c_ok" ;;
  esac

  summary
}

run_checks | tee "$REPORT"
say "report: $REPORT"
[ "$(tail -n 1 "$REPORT" | grep -c 'FAIL')" -eq 0 ] && grep -qE '^10/10 PASS$' "$REPORT"
