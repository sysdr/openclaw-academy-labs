#!/usr/bin/env bash
# PROOF: allowlist config is live in OpenClaw, and denied commands are refused
# by OpenClaw's real exec tool (not by a model's good manners).
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

CASES="${CASES:-$ROOT/fixtures/cases.json}"
DESIRED="${DESIRED:-$ROOT/config/exec-approvals.json}"
CANARY="$STATE/l04-canary"
mkdir -p "$REPORTS"
REPORT="$REPORTS/verify-$(date +%Y%m%d-%H%M%S).txt"

run_all() {
  prereqs
  echo "== Part A: the allowlist config is what OpenClaw enforces"
  if "$OC" health --json 2>/dev/null | "$PY" -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("ok") else 1)'; then
    pass "gateway healthy on loopback (from L03)"
  else
    fail "gateway healthy on loopback (from L03)" "start the gateway: openclaw gateway run --bind loopback"
  fi
  local execcfg
  execcfg="$("$OC" config get tools.exec --json 2>/dev/null || echo '{}')"
  # 2026.10.x accepts legacy security/ask or normalized mode ("ask" == allowlist + on-miss).
  if printf '%s' "$execcfg" | "$PY" -c 'import json,sys; c=json.load(sys.stdin); sys.exit(0 if c.get("security")=="allowlist" or c.get("mode") in ("ask","allowlist") else 1)'; then
    pass "tools.exec.security is allowlist"
  else
    fail "tools.exec.security is allowlist" "make setup"
  fi
  if printf '%s' "$execcfg" | "$PY" -c 'import json,sys; c=json.load(sys.stdin); sys.exit(0 if c.get("ask")=="on-miss" or c.get("mode")=="ask" else 1)'; then
    pass "tools.exec.ask is on-miss"
  else
    fail "tools.exec.ask is on-miss" "make setup"
  fi
  "$OC" approvals get --json >"$STATE/approvals-get.json" 2>/dev/null || echo '{}' >"$STATE/approvals-get.json"
  while IFS= read -r line; do
    status="${line%% *}"; label="${line#* }"
    if [ "$status" = "PASS" ]; then pass "$label"; else fail "$label" "make setup"; fi
  done < <("$PY" "$ROOT/src/l04.py" policy-check "$STATE/approvals-get.json" "$DESIRED" || true)

  if [ -z "${L04_MOCK:-}" ]; then
    missing="$("$PY" -c 'import json,os,sys; d=json.load(open(sys.argv[1])); print(" ".join(e["pattern"] for e in d["agents"]["main"]["allowlist"] if "*" not in e["pattern"] and e["pattern"].startswith("/") and not os.access(e["pattern"], os.X_OK)))' "$DESIRED")"
    if [ -z "$missing" ]; then pass "every allowlisted path exists on this host"
    else fail "every allowlisted path exists on this host" "not found: $missing (use: readlink -f \"\$(command -v NAME)\")"; fi
  fi

  echo "== Part B: commands through the real exec tool"
  probe_start
  rm -f "$CANARY"
  while IFS=$'\t' read -r name cmd expect canary; do
    before="$(log_lines)"
    probe_run "$cmd"
    got="$("$PY" "$ROOT/src/l04.py" classify "$L04_PROBE_LOG" "$cmd" "$before")"
    if [ "$got" = "$expect" ]; then pass "$name"; else fail "$name (expected $expect, got $got)" "see .state/last-agent.json"; fi
    if [ "$canary" = "1" ]; then
      if [ -e "$CANARY" ]; then fail "  side effect did not happen" "a denied command still ran: check tools.exec + approvals"; rm -f "$CANARY"
      else pass "  side effect did not happen"; fi
    fi
  done < <("$PY" "$ROOT/src/l04.py" cases "$CASES" "$CANARY")

  echo "$PASSES/$TOTAL PASS"
  [ "$PASSES" -eq "$TOTAL" ]
}

set +e
run_all 2>&1 | tee "$REPORT"
code="${PIPESTATUS[0]}"
set -e
echo "report: ${REPORT#"$ROOT"/}"
exit "$code"
