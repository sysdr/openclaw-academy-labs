#!/usr/bin/env bash
# Runs the real scripts/verify.sh against tests/mock_openclaw twice:
# once configured correctly (must exit 0, all PASS), once loose (must exit non-zero).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export OPENCLAW_BIN="$ROOT/tests/mock_openclaw" L04_MOCK=1 L04_PROBE_LOG="$tmp/probe.jsonl" L04_REPORTS="$tmp/reports"

if MOCK_STATE=pass bash "$ROOT/scripts/verify.sh" >"$tmp/pass.txt" 2>&1 && grep -Eq '^([0-9]+)/\1 PASS$' "$tmp/pass.txt"; then
  echo "mock pass state: verify.sh exit 0, all checks PASS   PASS"
else
  echo "mock pass state                                     FAIL"; cat "$tmp/pass.txt"; exit 1
fi
if MOCK_STATE=fail bash "$ROOT/scripts/verify.sh" >"$tmp/fail.txt" 2>&1; then
  echo "mock fail state: verify.sh should have failed         FAIL"; cat "$tmp/fail.txt"; exit 1
else
  grep -q 'side effect did not happen.*FAIL' "$tmp/fail.txt" || { echo "fail state did not catch the canary   FAIL"; exit 1; }
  echo "mock fail state: verify.sh exit non-zero, canary caught   PASS"
fi
