#!/usr/bin/env bash
# build.sh - nothing to compile; validate the config fragment and helper code instead.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

frag="$ROOT/config/openclaw.gateway.json5"
if [ "$(python3 "$GWCHECK" get "$frag" gateway.bind)" = '"loopback"' ]; then pass "fragment: gateway.bind = loopback"
else fail "fragment: gateway.bind = loopback" "edit $frag"; fi
if [ "$(python3 "$GWCHECK" get "$frag" gateway.auth.mode)" = '"token"' ]; then pass "fragment: gateway.auth.mode = token"
else fail "fragment: gateway.auth.mode = token" "edit $frag"; fi
if [ "$(python3 "$GWCHECK" literal-token "$frag")" = "no" ]; then pass "fragment: no literal token"
else fail "fragment: no literal token" "remove gateway.auth.token from $frag"; fi
if python3 -m py_compile "$GWCHECK" "$ROOT/tests/mock_gateway.py"; then pass "python sources compile"
else fail "python sources compile" "see error above"; fi

summary
[ "$FAIL_COUNT" -eq 0 ]
