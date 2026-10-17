#!/usr/bin/env bash
# SC2016: the bash -c snippets read their own positional args on purpose.
# SC2329: helper functions below are called through check().
# shellcheck disable=SC2016,SC2329
# verify: prove the PROOF for Lesson 01: a sandboxed agent answers its first
# message. Prints one PASS/FAIL line per check, then "N/N PASS". Exit 0 only if
# every check passes. Writes a timestamped copy to reports/.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
load_env
PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
CHECKS="python3 $ROOT/src/l01_checks.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$ROOT/reports"
REPORT="$ROOT/reports/verify-$(date +%Y%m%d-%H%M%S).txt"

fact() { grep -qx "$1=true" "$TMP/inspect.txt"; }
nofact() { grep -qx "$1=false" "$TMP/inspect.txt"; }

run_checks() {
  echo "Lesson 01 verify: sandboxed agent answers its first message"
  check "1. Docker daemon reachable" docker info

  CID="$(compose ps -q openclaw-gateway 2>/dev/null | head -n 1 || true)"
  if [ -n "$CID" ] && docker inspect "$CID" > "$TMP/inspect.json" 2>/dev/null; then
    $CHECKS inspect "$TMP/inspect.json" > "$TMP/inspect.txt" 2>/dev/null || : > "$TMP/inspect.txt"
  else
    : > "$TMP/inspect.txt"
  fi
  check "2. Gateway container running"                    fact running
  check "3. Container healthcheck reports healthy"        fact healthy
  check "4. Gateway process is not root (uid != 0)" \
    bash -c '[ -n "$1" ] && u="$(docker exec "$1" id -u)" && [ "$u" != "0" ]' _ "${CID:-}"
  check "5. no-new-privileges is set"                     fact no_new_privileges
  check "6. All capabilities dropped, not privileged" \
    bash -c 'grep -qx cap_drop_all=true "$1" && grep -qx privileged=false "$1"' _ "$TMP/inspect.txt"
  check "7. Docker socket not mounted into the sandbox"   nofact docker_sock_mounted

  docker port "${CID:-none}" 18789/tcp > "$TMP/ports.txt" 2>/dev/null || : > "$TMP/ports.txt"
  check "8. Host port published on loopback only" \
    bash -c '[ "$($1 ports "$2")" = PASS ]' _ "$CHECKS" "$TMP/ports.txt"
  check "9. Gateway admits traffic (/startupz = 200)" \
    bash -c '[ "$(http_code_fn "$1")" = 200 ]' _ "http://127.0.0.1:$PORT/startupz"

  : > "$TMP/policy.json"; : > "$TMP/reply.json"; : > "$TMP/reply.err"
  if gateway_running; then
    oc approvals get --gateway --json > "$TMP/policy.json" 2>/dev/null || true
  fi
  check "10. Exec policy is deny (agent cannot run commands)" \
    bash -c '[ "$($1 policy "$2")" = PASS ]' _ "$CHECKS" "$TMP/policy.json"

  NONCE="SANDBOX-OK-$(python3 -c 'import secrets; print(secrets.token_hex(4))')"
  if gateway_running; then
    oc agent --agent main --timeout 120 --json \
      --message "Reply with exactly this token and nothing else: $NONCE" \
      > "$TMP/reply.json" 2>"$TMP/reply.err" || true
  else
    echo "gateway not running (make run)" > "$TMP/reply.err"
  fi
  check "11. Agent answered first message with fresh token" \
    bash -c '[ "$($1 reply "$2" "$3")" = PASS ]' _ "$CHECKS" "$TMP/reply.json" "$NONCE"
  if grep -q '"text"' "$TMP/reply.json" 2>/dev/null; then
    echo "   agent said: $($CHECKS text "$TMP/reply.json" 2>/dev/null | head -c 200)"
  elif [ -s "$TMP/reply.err" ] || [ -s "$TMP/reply.json" ]; then
    # Prefer the actionable line (quota/auth/model), not the generic "run doctor" footer.
    err="$(grep -Eio '.{0,40}(429|quota|RESOURCE_EXHAUSTED|API key|Unauthorized|404|model[^[:space:]]*).{0,120}' \
      "$TMP/reply.err" "$TMP/reply.json" 2>/dev/null | head -n 1 || true)"
    if [ -z "$err" ]; then
      err="$(grep -v 'For help, run' "$TMP/reply.err" 2>/dev/null | tail -n 3 | tr '\n' ' ' | head -c 240)"
    fi
    [ -z "$err" ] && err="$(tail -n 1 "$TMP/reply.err" 2>/dev/null | head -c 200)"
    echo "   agent error: ${err:-unknown (see compose logs)}"
  fi
  summary
}

# http_code is a shell function; export it so the bash -c checks can call it.
http_code_fn() { http_code "$@"; }
export -f http_code http_code_fn

set +e
run_checks 2>&1 | tee "$REPORT"
status="${PIPESTATUS[0]}"
set -e
echo "Report: ${REPORT#"$ROOT"/}"
exit "$status"
