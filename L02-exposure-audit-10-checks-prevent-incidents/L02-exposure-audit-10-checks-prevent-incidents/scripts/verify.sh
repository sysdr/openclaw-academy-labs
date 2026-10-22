#!/usr/bin/env bash
# verify: the lesson proof. Runs the exposure audit and passes only when
# all 10 checks are green. Writes a timestamped report to reports/.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
EXPECTED=10
mkdir -p "$ROOT/reports"
report="$ROOT/reports/verify-$(date -u +%Y%m%dT%H%M%SZ).txt"

set +e
"$ROOT/scripts/audit.sh" 2>&1 | tee "$report"
set -e
last="$(tail -n 1 "$report")"
echo "Report: ${report#"$ROOT"/}"
if [ "$last" = "$EXPECTED/$EXPECTED PASS" ]; then
  exit 0
fi
echo "Not all $EXPECTED checks are green. Each FAIL line names what to fix; see 'If it breaks' in the lesson." >&2
exit 1
