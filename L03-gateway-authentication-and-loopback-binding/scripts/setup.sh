#!/usr/bin/env bash
# setup.sh - generate a strong token into .env and apply the two locks to your config.
# Safe to run twice: it never overwrites an existing token and asks before removing one.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

if python_ok; then pass "prerequisite: python3 >= 3.11"
else fail "prerequisite: python3 >= 3.11" "install Python 3.11+"; summary; exit 1; fi

# 1. Token lives in .env (mode 600), never in openclaw.json and never on screen.
if grep -qE '^OPENCLAW_GATEWAY_TOKEN=.{32,}' "$ROOT/.env" 2>/dev/null; then
  pass "token already in .env (left unchanged)"
else
  if command -v openssl >/dev/null 2>&1; then tok="$(openssl rand -hex 32)"
  else tok="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"; fi
  ( umask 077; printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$tok" >> "$ROOT/.env" )
  unset tok
  pass "generated 256-bit token into .env"
fi
chmod 600 "$ROOT/.env"
pass ".env permissions are 600"

# 2. Config: bind loopback + token auth, via the official CLI when available.
if command -v openclaw >/dev/null 2>&1; then
  openclaw config set gateway.mode local >/dev/null && pass "config set gateway.mode local"
  openclaw config set gateway.bind loopback >/dev/null && pass "config set gateway.bind loopback"
  openclaw config set gateway.auth.mode token >/dev/null && pass "config set gateway.auth.mode token"
  if [ -f "$CONFIG_PATH" ] && [ "$(python3 "$GWCHECK" literal-token "$CONFIG_PATH")" = "yes" ]; then
    say "A literal gateway.auth.token is stored in $CONFIG_PATH."
    if confirm "Remove it so the Gateway reads OPENCLAW_GATEWAY_TOKEN instead?"; then
      openclaw config unset gateway.auth.token >/dev/null && pass "removed literal token from config"
    else
      fail "literal token left in config" "rerun setup interactively, or: openclaw config unset gateway.auth.token"
    fi
  else
    pass "no literal token in config"
  fi
else
  fail "openclaw CLI found" "merge config/openclaw.gateway.json5 into $CONFIG_PATH by hand"
fi

summary
[ "$FAIL_COUNT" -eq 0 ]
