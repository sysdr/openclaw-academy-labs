#!/usr/bin/env bash
# clean.sh - remove generated reports and caches. Asks before touching .env (your token).
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

rm -rf "$ROOT/reports" && pass "removed reports/"
find "$ROOT" -name '__pycache__' -type d -prune -exec rm -rf {} + && pass "removed __pycache__"
if [ -f "$ROOT/.env" ]; then
  if confirm "Delete .env (your Gateway token)? Clients using it will stop working."; then
    rm -f "$ROOT/.env" && pass "removed .env"
  else
    say ".env kept"
  fi
fi
summary
