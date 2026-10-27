#!/usr/bin/env bash
# Unit tests (no OpenClaw needed) plus the mock end-to-end test of verify.sh.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
cd "$ROOT"
check "unit + integration tests (integration skips without openclaw)" "$PY" -m unittest discover -s tests -q
check "verify.sh end-to-end against the mock (pass and fail states)" bash tests/e2e_mock.sh
echo "$PASSES/$TOTAL PASS"
[ "$PASSES" -eq "$TOTAL" ]
