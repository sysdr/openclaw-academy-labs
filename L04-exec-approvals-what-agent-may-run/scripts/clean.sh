#!/usr/bin/env bash
# Stops the probe and removes local run state. Reports and approval backups are kept.
# RESTORE=1 puts back the newest approvals backup (asks first).
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
probe_stop
pass "probe model stopped"
rm -f "$STATE/probe.out" "$STATE/last-agent.json" "$STATE/approvals-get.json" "$STATE/l04-canary" "$L04_PROBE_LOG"
pass "run state removed (backups and reports kept)"
if [ "${RESTORE:-}" = "1" ]; then
  latest="$(find "$STATE" -name 'approvals-backup-*.json' | sort | tail -n 1)"
  [ -n "$latest" ] || die "no backup found"
  read -r -p "Restore ${latest#"$ROOT"/}? This replaces current approvals. [y/N] " answer
  case "$answer" in y|Y) "$OC" approvals set --file "$latest" >/dev/null && pass "approvals restored";; *) echo "skipped restore";; esac
fi
echo "$PASSES/$TOTAL PASS"
