#!/usr/bin/env bash
# Shared helpers for Lesson 03 scripts. Sourced, not executed.
# shellcheck disable=SC2034  # variables are used by the scripts that source this file

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GWCHECK="$ROOT/src/gwcheck.py"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
PASS_COUNT=0
FAIL_COUNT=0

# Ensure OpenClaw/Node are findable even when the shell never loaded nvm.
# Prefer an already-on-PATH openclaw; otherwise prepend common install locations.
if ! command -v openclaw >/dev/null 2>&1; then
  for d in \
    "${HOME}/.local/bin" \
    "${HOME}/.nvm/versions/node/$(ls -1 "${HOME}/.nvm/versions/node" 2>/dev/null | sort -V | tail -n 1)/bin"
  do
    if [ -x "${d}/openclaw" ]; then
      PATH="${d}:${PATH}"
      export PATH
      break
    fi
  done
fi

say()  { printf '%s\n' "$*"; }
pass() { printf '%-58s PASS\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '%-58s FAIL  (%s)\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

need() {
  # need <command> <how to fix>
  if command -v "$1" >/dev/null 2>&1; then
    pass "prerequisite: $1"
  else
    fail "prerequisite: $1" "$2"
  fi
}

python_ok() {
  command -v python3 >/dev/null 2>&1 &&
    python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'
}

# Load OPENCLAW_GATEWAY_TOKEN from .env without sourcing it (never echo it).
load_token() {
  if [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ] && [ -f "$ROOT/.env" ]; then
    local line
    line="$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' "$ROOT/.env" | tail -n 1 || true)"
    if [ -n "$line" ]; then
      OPENCLAW_GATEWAY_TOKEN="${line#OPENCLAW_GATEWAY_TOKEN=}"
      OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN%\"}"
      OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN#\"}"
      export OPENCLAW_GATEWAY_TOKEN
    fi
  fi
}

# Port precedence documented by OpenClaw: --port > OPENCLAW_GATEWAY_PORT > gateway.port > 18789
resolve_port() {
  if [ -n "${OPENCLAW_GATEWAY_PORT:-}" ]; then
    printf '%s' "$OPENCLAW_GATEWAY_PORT"; return
  fi
  local p
  p="$(python3 "$GWCHECK" get "$CONFIG_PATH" gateway.port 2>/dev/null || echo null)"
  if [[ "$p" =~ ^[0-9]+$ ]]; then printf '%s' "$p"; else printf '18789'; fi
}

confirm() {
  # confirm "question" -> returns 0 on y/yes. Non-interactive shells answer no.
  [ -t 0 ] || return 1
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

summary() {
  local total=$((PASS_COUNT + FAIL_COUNT))
  say "----"
  if [ "$FAIL_COUNT" -eq 0 ]; then
    say "$PASS_COUNT/$total PASS"
  else
    say "$PASS_COUNT/$total PASS ($FAIL_COUNT FAIL)"
  fi
}
