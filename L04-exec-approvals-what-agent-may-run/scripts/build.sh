#!/usr/bin/env bash
# Validates every config file before anything touches OpenClaw.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
for f in config/exec-approvals.json config/openclaw.exec.patch.json fixtures/cases.json solution/exec-approvals.json solution/cases.json; do
  check "valid JSON: $f" "$PY" -m json.tool "$ROOT/$f"
done
check "approvals config passes its own policy check" "$PY" "$ROOT/src/l04.py" policy-check \
  <("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({"file":d,"effectivePolicy":{"scopes":[{"agentId":"main","security":{"effective":"allowlist"}}]}}))' "$ROOT/config/exec-approvals.json") \
  "$ROOT/config/exec-approvals.json"
if have "$OC" || [ -x "$OC" ]; then
  check "openclaw accepts the config patch (dry run)" "$OC" config patch --file "$ROOT/config/openclaw.exec.patch.json" --dry-run
fi
echo "$PASSES/$TOTAL PASS"
[ "$PASSES" -eq "$TOTAL" ]
