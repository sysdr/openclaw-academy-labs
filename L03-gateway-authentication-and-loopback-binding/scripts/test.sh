#!/usr/bin/env bash
# test.sh - unit tests, mock end-to-end test, live test (auto-skipped), shellcheck.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

cd "$ROOT"
if python3 -m unittest discover -s tests -p 'test_*.py' 2>&1 | tail -n 3 | grep -q '^OK'; then
  pass "python tests (unit + mock e2e + live if available)"
else
  fail "python tests" "run: python3 -m unittest discover -s tests -v"
fi
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x scripts/*.sh solution/*.sh; then pass "shellcheck clean"
  else fail "shellcheck clean" "see warnings above"; fi
else
  say "shellcheck not installed (pip install shellcheck-py) - skipped"
fi
summary
[ "$FAIL_COUNT" -eq 0 ]
