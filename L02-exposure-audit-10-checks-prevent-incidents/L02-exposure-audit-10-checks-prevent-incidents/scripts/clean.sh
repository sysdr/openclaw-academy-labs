#!/usr/bin/env bash
# clean: stop the gateway. Deletes state/, reports/ and .env only if you type yes.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
if [ -f "$ENV_FILE" ]; then
  load_env
  compose down >/dev/null 2>&1 || true
  echo "Gateway stopped."
fi
printf 'Also delete state/, reports/ and .env (your gateway token and config)? Type yes: '
read -r answer || answer=""
if [ "$answer" = "yes" ]; then
  rm -rf -- "$ROOT/state" "$ROOT/reports"
  rm -f -- "$ENV_FILE"
  echo "Deleted."
else
  echo "Kept."
fi
