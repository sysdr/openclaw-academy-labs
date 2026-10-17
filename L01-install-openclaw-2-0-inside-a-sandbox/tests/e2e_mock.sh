#!/usr/bin/env bash
# End-to-end test of the real scripts/verify.sh against mock docker/curl:
# once in a passing state (expect 11/11 PASS, exit 0) and once in a failing
# state (expect the exact FAIL lines in expected/verify.txt, exit != 0).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
printf 'OPENCLAW_GATEWAY_PORT=18789\n' > "$WORK/.env"
export PATH="$ROOT/tests/mock:$PATH" L01_ENV_FILE="$WORK/.env"
fails=0

normalize() {  # keep only check lines and the total; drop report path and agent text
  grep -E '^([0-9]+\. |[0-9]+/[0-9]+ PASS)' | sed -E 's/[[:space:]]+(PASS|FAIL)$/ \1/'
}

for state in pass fail; do
  set +e
  out="$(MOCK_STATE="$state" bash "$ROOT/scripts/verify.sh" 2>&1)"; code=$?
  set -e
  got="$(printf '%s\n' "$out" | normalize)"
  want="$(awk -v s="## $state" 'index($0, "## ") == 1 {on = (index($0, s) == 1); next} on' \
    "$ROOT/expected/verify.txt" | normalize)"
  if [ "$got" = "$want" ]; then echo "mock $state: output matches expected/verify.txt ($state) PASS"
  else echo "mock $state: output differs from expected FAIL"; diff <(echo "$want") <(echo "$got") || true; fails=$((fails + 1)); fi
  if { [ "$state" = pass ] && [ "$code" -eq 0 ]; } || { [ "$state" = fail ] && [ "$code" -ne 0 ]; }; then
    echo "mock $state: exit code $code as expected PASS"
  else echo "mock $state: unexpected exit code $code FAIL"; fails=$((fails + 1)); fi
done
if [ "$fails" -eq 0 ]; then echo "e2e mock: 4/4 PASS"; else echo "e2e mock: $fails FAIL"; exit 1; fi
