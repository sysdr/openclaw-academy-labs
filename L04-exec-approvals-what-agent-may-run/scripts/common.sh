#!/usr/bin/env bash
# Shared helpers for L04 scripts. Sourced, never run directly.
# shellcheck disable=SC2034  # variables are used by the scripts that source this file
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/.state"
REPORTS="${L04_REPORTS:-$ROOT/reports}"
mkdir -p "$STATE"

# OPENCLAW_BIN (one executable path) lets tests swap in tests/mock_openclaw. Default: the CLI on PATH.
OC="${OPENCLAW_BIN:-openclaw}"
PY="${PYTHON:-python3}"
PROBE_PORT="${L04_PROBE_PORT:-18999}"
export L04_PROBE_LOG="${L04_PROBE_LOG:-$STATE/probe-results.jsonl}"
PROBE_PID="$STATE/probe.pid"
MIN_VERSION="2026.8.1"   # argPattern semantics changed in 2026.8.1 (docs: exec approvals)

PASSES=0
TOTAL=0
pass() { PASSES=$((PASSES + 1)); TOTAL=$((TOTAL + 1)); printf '%-62s PASS\n' "$1"; }
fail() { TOTAL=$((TOTAL + 1)); printf '%-62s FAIL\n' "$1"; [ -n "${2:-}" ] && printf '    fix: %s\n' "$2"; return 0; }
check() { if "${@:2}" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

oc_version_ok() {
  local raw
  raw="$("$OC" --version 2>/dev/null | head -n1)" || return 1
  "$PY" - "$raw" "$MIN_VERSION" <<'PYEOF'
import re, sys
found = re.search(r"(\d{4})\.(\d+)\.(\d+)", sys.argv[1])
need = tuple(int(x) for x in sys.argv[2].split("."))
sys.exit(0 if found and tuple(int(x) for x in found.groups()) >= need else 1)
PYEOF
}

# Prerequisite gate: one line each, clear fix, stop before touching anything.
prereqs() {
  local bad=0
  if have "$PY"; then pass "prereq: python3 present"; else fail "prereq: python3 present" "install Python 3.11+"; bad=1; fi
  if have "$OC" || [ -x "$OC" ]; then pass "prereq: openclaw CLI present"
  else fail "prereq: openclaw CLI present" "run this inside your L01 sandbox, or set OPENCLAW_BIN"; bad=1; fi
  if [ "$bad" -eq 0 ] && oc_version_ok; then pass "prereq: openclaw >= $MIN_VERSION"
  else fail "prereq: openclaw >= $MIN_VERSION" "openclaw update (then rerun)"; bad=1; fi
  [ "$bad" -eq 0 ] || die "prerequisites missing; fix the lines marked FAIL"
  PASSES=0; TOTAL=0
}

port_open() {
  # Prefer a real TCP connect via python (works on macOS, Linux, WSL2 without ss/lsof).
  "$PY" - "$1" <<'PYEOF'
import socket, sys
s = socket.socket(); s.settimeout(1)
sys.exit(0 if s.connect_ex(("127.0.0.1", int(sys.argv[1]))) == 0 else 1)
PYEOF
}

probe_start() {
  if [ -n "${L04_MOCK:-}" ]; then return 0; fi
  if [ -f "$PROBE_PID" ] && kill -0 "$(cat "$PROBE_PID")" 2>/dev/null && port_open "$PROBE_PORT"; then return 0; fi
  if port_open "$PROBE_PORT"; then die "port $PROBE_PORT is busy with something else; set L04_PROBE_PORT"; fi
  nohup "$PY" "$ROOT/src/probe_model.py" "$PROBE_PORT" >"$STATE/probe.out" 2>&1 &
  echo $! >"$PROBE_PID"
  for _ in 1 2 3 4 5 6 7 8 9 10; do port_open "$PROBE_PORT" && return 0; sleep 0.5; done
  die "probe model did not start; see $STATE/probe.out"
}

probe_stop() {
  if [ -f "$PROBE_PID" ]; then kill "$(cat "$PROBE_PID")" 2>/dev/null || true; rm -f "$PROBE_PID"; fi
}

# Ask the real agent (via the scripted probe model) to run one command through the exec tool.
probe_run() {
  local cmd="$1" key
  key="agent:main:l04-probe-$(date +%s)-$RANDOM"
  "$OC" agent --agent main --model probe/exec-probe --session-key "$key" \
    --message "RUN: $cmd" --json --timeout "${L04_AGENT_TIMEOUT:-120}" >"$STATE/last-agent.json" 2>&1 || true
}

log_lines() { if [ -f "$L04_PROBE_LOG" ]; then wc -l <"$L04_PROBE_LOG" | tr -d ' '; else echo 0; fi; }
