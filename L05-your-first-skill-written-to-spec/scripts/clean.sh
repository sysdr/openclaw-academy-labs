#!/usr/bin/env bash
# Stop the probe and remove local lesson state. Asks before touching your workspace.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
stop_probe
check "probe stopped" sh -c "! python3 -c 'import urllib.request; urllib.request.urlopen(\"http://127.0.0.1:$PROBE_PORT/health\", timeout=1)'"
if command -v "$OPENCLAW" >/dev/null 2>&1 && ws=$(workspace_dir); then
  if [ -d "$ws/skills/$NEG_NAME" ]; then rm -rf "${ws:?}/skills/$NEG_NAME"; fi
  if [ -d "$ws/skills/$SKILL_NAME" ] && confirm "Remove $SKILL_NAME from $ws/skills?"; then
    rm -rf "${ws:?}/skills/$SKILL_NAME"
  fi
  echo "The probe provider stays in openclaw.json; remove it with: openclaw config set models.providers.probe null"
fi
rm -rf "$STATE_DIR"
check "local state removed" test ! -d "$STATE_DIR"
total
