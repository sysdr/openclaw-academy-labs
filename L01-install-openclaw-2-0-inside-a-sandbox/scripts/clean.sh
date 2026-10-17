#!/usr/bin/env bash
# clean: stop and remove the lesson containers and network. Deleting state/
# (config, sessions, credentials) and .env happens only after you type "yes".
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
if command -v docker >/dev/null 2>&1 && [ -f "$ENV_FILE" ]; then
  compose down --remove-orphans || true
fi
rm -rf "$ROOT/reports" "$ROOT/tests/__pycache__" "$ROOT/src/__pycache__"
if [ -d "$STATE_DIR" ] && [ -t 0 ]; then
  printf 'Also delete %s and .env (agent config, sessions, gateway token)? Type yes to confirm: ' "$STATE_DIR"
  read -r answer
  if [ "$answer" = "yes" ]; then
    rm -rf "$STATE_DIR" "$ENV_FILE" && echo "Deleted state and .env."
  else
    echo "Kept state/ and .env."
  fi
else
  echo "Kept state/ and .env (run interactively to delete them)."
fi
