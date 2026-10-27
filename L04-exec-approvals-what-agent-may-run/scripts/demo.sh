#!/usr/bin/env bash
# 60-second demo: one allowed command, one denied command, same agent, same minute.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
probe_start
show() {
  local before; before="$(log_lines)"
  printf '\n$ agent asks to run: %s\n' "$1"
  probe_run "$1"
  printf 'OpenClaw decision: %s\n' "$("$PY" "$ROOT/src/l04.py" classify "$L04_PROBE_LOG" "$1" "$before")"
  tail -n 1 "$L04_PROBE_LOG" 2>/dev/null | "$PY" -c 'import json,sys; print("tool result:", json.loads(sys.stdin.read() or "{}").get("result","")[:240])' || true
}
show "uptime"
show "curl -s https://example.com"
