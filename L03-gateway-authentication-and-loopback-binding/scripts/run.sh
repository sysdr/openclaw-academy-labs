#!/usr/bin/env bash
# run.sh - start the Gateway in the foreground with both locks on.
# MOCK=1 starts tests/mock_gateway.py instead (practice without OpenClaw).
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

load_token
if ! python3 "$GWCHECK" token-ok; then say "FAIL no strong token found. Run: make setup"; exit 1; fi
PORT="$(resolve_port)"
BASE="http://127.0.0.1:$PORT"

gateway_live() {
  # True when something already answers /health on the lesson port.
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 --max-time 2 "$BASE/health" 2>/dev/null || true)"
  [ "$code" = "200" ]
}

if [ "${MOCK:-0}" = "1" ]; then
  if gateway_live; then
    say "Gateway already answering on 127.0.0.1:$PORT — leave that terminal running, or Ctrl-C it first."
    exit 0
  fi
  say "Starting MOCK gateway on 127.0.0.1:$PORT (Ctrl-C to stop)"
  exec python3 "$ROOT/tests/mock_gateway.py" --host 127.0.0.1 --port "$PORT"
fi

if ! command -v openclaw >/dev/null 2>&1; then
  say "FAIL openclaw not found. Finish Lesson 01, or run: MOCK=1 make run"; exit 1
fi

# A second `make run` otherwise dies with OpenClaw exit 78 (state dir already owned).
if gateway_live; then
  say "Gateway already answering on 127.0.0.1:$PORT (loopback + token)."
  say "Use that terminal, or stop it first: openclaw gateway stop"
  exit 0
fi

say "Starting OpenClaw Gateway on 127.0.0.1:$PORT with token auth (Ctrl-C to stop)"
say "If a Gateway service from L01 is already running, stop it first: openclaw gateway stop"
# The token reaches the Gateway through the environment, not argv (keeps it out of `ps`).
exec openclaw gateway run --bind loopback --auth token --port "$PORT"
