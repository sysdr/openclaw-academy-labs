#!/usr/bin/env bash
# Recreates the end state of L03 (gateway on loopback with token auth) for readers who skipped it.
# Reuses L01 (OpenClaw installed in a sandbox) and L03 (loopback + token). Does not create secrets.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
prereqs
echo '{"gateway":{"mode":"local","bind":"loopback","auth":{"mode":"token"}}}' | "$OC" config patch --stdin >/dev/null
pass "L03 state: gateway.bind=loopback, gateway.auth.mode=token"
if [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
  fail "OPENCLAW_GATEWAY_TOKEN is set in this shell" \
    "export OPENCLAW_GATEWAY_TOKEN=\"\$(openssl rand -hex 32)\" (keep it out of files; see L03)"
else
  pass "OPENCLAW_GATEWAY_TOKEN is set in this shell"
fi
if "$OC" health --json >/dev/null 2>&1; then pass "gateway answers on loopback"
else fail "gateway answers on loopback" "openclaw gateway run --bind loopback --auth token   (separate terminal)"; fi
echo "$PASSES/$TOTAL PASS"
[ "$PASSES" -eq "$TOTAL" ]
