#!/usr/bin/env bash
# Run the real scripts/verify.sh against tests/mock_openclaw.py twice:
#   pass state -> must print 16/16 PASS and exit 0
#   fail state -> exec denied, must exit non-zero and FAIL the reply checks
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/l05-e2e.XXXXXX")"
PORT=$((20000 + RANDOM % 20000))
# shellcheck disable=SC2329  # invoked by the EXIT trap
cleanup() {
  if [ -f "$TMP/state/probe.pid" ]; then kill "$(cat "$TMP/state/probe.pid")" 2>/dev/null || true; fi
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$TMP/bin" "$TMP/oc/workspace/skills/uptime-report"
cp "$ROOT/skills/uptime-report/SKILL.md" "$TMP/oc/workspace/skills/uptime-report/SKILL.md"
printf '#!/bin/sh\nexec python3 "%s" "$@"\n' "$HERE/mock_openclaw.py" > "$TMP/bin/openclaw"
chmod +x "$TMP/bin/openclaw"

run() { # run MODE -> output in $TMP/MODE.out, exit code echoed
  set +e
  MOCK_OC_HOME="$TMP/oc" MOCK_OC_MODE="$1" OPENCLAW_BIN="$TMP/bin/openclaw" L05_PROBE_PORT="$PORT" \
    L05_STATE_DIR="$TMP/state" L05_REPORT_DIR="$TMP/reports" bash "$ROOT/scripts/verify.sh" > "$TMP/$1.out" 2>&1
  echo $?
  set -e
}

ok=0
rc=$(run pass)
if [ "$rc" = 0 ] && grep -q '^16/16 PASS$' "$TMP/pass.out"; then echo "mock pass state: 16/16 PASS, exit 0   PASS"
else echo "mock pass state                       FAIL"; cat "$TMP/pass.out"; ok=1; fi

rc=$(run fail)
if [ "$rc" != 0 ] && grep -q '^C3 .*FAIL$' "$TMP/fail.out" && grep -q '^C4 .*FAIL$' "$TMP/fail.out"; then
  echo "mock fail state: C3+C4 FAIL, exit $rc   PASS"
else echo "mock fail state                       FAIL"; cat "$TMP/fail.out"; ok=1; fi

ls "$TMP/reports"/verify-*.txt >/dev/null 2>&1 || { echo "no timestamped report written   FAIL"; ok=1; }
exit "$ok"
