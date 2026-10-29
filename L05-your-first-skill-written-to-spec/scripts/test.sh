#!/usr/bin/env bash
# Unit tests (no OpenClaw needed) plus verify.sh end to end against the mock.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need_python
check "unit + integration tests (integration skips without openclaw)" \
  python3 -m unittest discover -s "$LESSON_DIR/tests" -p 'test_*.py'
check "verify.sh end to end against the mock (pass and fail states)" \
  bash "$LESSON_DIR/tests/e2e_verify_mock.sh"
if [ "$FAIL_N" -gt 0 ]; then
  echo "--- details ---"
  python3 -m unittest discover -s "$LESSON_DIR/tests" -p 'test_*.py' 2>&1 | tail -20 || true
  bash "$LESSON_DIR/tests/e2e_verify_mock.sh" 2>&1 | tail -20 || true
fi
total
