#!/usr/bin/env bash
# demo: about 60 seconds. Flip one risky setting, watch the audit catch it,
# put it back, watch it go green. The setting is restored even on Ctrl-C.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
load_env

restore() { oc config set discovery.mdns.mode off >/dev/null 2>&1 || true; }
trap restore EXIT
echo "== 1/2 Simulate drift: discovery.mdns.mode=full (broadcasts host details on your LAN)"
oc config set discovery.mdns.mode full >/dev/null
"$ROOT/scripts/audit.sh" | grep -E 'FAIL|PASS$' || true

echo "== 2/2 Restore and re-audit"
restore
trap - EXIT
"$ROOT/scripts/audit.sh" | tail -n 1
