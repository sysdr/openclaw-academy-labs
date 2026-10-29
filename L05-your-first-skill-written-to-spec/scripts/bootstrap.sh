#!/usr/bin/env bash
# Recreate the end state of Lessons 03 and 04 for readers who skipped them:
#   L03: gateway bound to loopback with token auth
#   L04: deny-by-default exec allowlist (uptime, ls, two git subcommands)
# Safe to run twice: it changes nothing that already matches.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need_python
need_openclaw

# L03 end state (reused, not re-taught)
bind=$("$OPENCLAW" config get gateway.bind 2>/dev/null || true)
auth=$("$OPENCLAW" config get gateway.auth.mode 2>/dev/null || true)
if [ "$bind" != "loopback" ] || [ "$auth" != "token" ]; then
  "$OPENCLAW" config set gateway.bind loopback >/dev/null
  "$OPENCLAW" config set gateway.auth.mode token >/dev/null
  echo "L03 settings applied; restart the gateway: openclaw gateway restart"
fi
check "L03 state: gateway.bind=loopback" test "$("$OPENCLAW" config get gateway.bind)" = loopback
check "L03 state: gateway.auth.mode=token" test "$("$OPENCLAW" config get gateway.auth.mode)" = token

# L04 end state: tools.exec request policy
"$OPENCLAW" config get tools.exec --json > "$STATE_DIR/tools-exec.json" 2>/dev/null || echo '{}' > "$STATE_DIR/tools-exec.json"
if [ "$(jget "$STATE_DIR/tools-exec.json" 'd.get("security","")')" != "allowlist" ]; then
  "$OPENCLAW" config set tools.exec.security allowlist >/dev/null
  "$OPENCLAW" config set tools.exec.ask on-miss >/dev/null
  "$OPENCLAW" config set tools.exec.strictInlineEval true >/dev/null
fi
check "L04 state: tools.exec.security=allowlist" test "$("$OPENCLAW" config get tools.exec.security)" = allowlist

# L04 end state: host approvals. 'approvals set' replaces the whole document, so back up and ask.
"$OPENCLAW" approvals get --json > "$STATE_DIR/approvals-now.json"
has_uptime=$(jget "$STATE_DIR/approvals-now.json" \
  'any(e.get("pattern","").endswith("/uptime") for e in d["file"].get("agents",{}).get("main",{}).get("allowlist",[]))')
if [ "$has_uptime" != "True" ]; then
  backup="$STATE_DIR/approvals-backup-$(date +%Y%m%d-%H%M%S).json"
  cp "$STATE_DIR/approvals-now.json" "$backup"
  if confirm "Replace exec approvals with the L04 allowlist (backup: $backup)?"; then
    "$OPENCLAW" approvals set --file "$LESSON_DIR/config/l04-exec-approvals.json" >/dev/null
  else
    echo "skipped: rerun with L05_YES=1 or apply config/l04-exec-approvals.json yourself"
  fi
fi
"$OPENCLAW" approvals get --json > "$STATE_DIR/approvals-now.json"
check "L04 state: uptime is on the main agent's allowlist" test "$(jget "$STATE_DIR/approvals-now.json" \
  'any(e.get("pattern","").endswith("/uptime") for e in d["file"].get("agents",{}).get("main",{}).get("allowlist",[]))')" = True
check "gateway answers health check" "$OPENCLAW" health --json
total
