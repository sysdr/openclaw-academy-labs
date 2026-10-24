#!/usr/bin/env bash
# bootstrap.sh - recreate the end state of L01 + L02 for readers who skipped them.
# L01 (install inside a sandbox) and L02 (exposure audit) are reused, not rebuilt.
# Safe to rerun: existing CLI, config, and L02 results are kept.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

say "Checking the end state of Lessons 01 and 02"

# L01: OpenClaw installed inside your sandbox (Docker or VM).
if command -v openclaw >/dev/null 2>&1; then
  pass "L01 openclaw CLI installed ($(openclaw --version 2>/dev/null | head -n 1))"
else
  fail "L01 openclaw CLI installed" "complete Lesson 01, or see https://docs.openclaw.ai/install"
fi

# L01: a config file exists (onboarding writes gateway.mode=local).
# Recreate a minimal local-mode config when the CLI is present but onboarding was skipped.
if [ -f "$CONFIG_PATH" ]; then
  pass "L01 config present at $CONFIG_PATH"
elif command -v openclaw >/dev/null 2>&1; then
  mkdir -p "$(dirname "$CONFIG_PATH")"
  if openclaw config set gateway.mode local >/dev/null 2>&1; then
    pass "L01 config present at $CONFIG_PATH"
  else
    fail "L01 config present at $CONFIG_PATH" "run: openclaw onboard --mode local"
  fi
else
  fail "L01 config present at $CONFIG_PATH" "run: openclaw onboard --mode local"
fi

# L02: reuse the audit script if the L02 folder sits next to this one
# (flat sibling, or double-nested zip layout used in the academy monorepo).
L02_VERIFY=""
for f in \
  "$ROOT"/../L02-*/scripts/verify.sh \
  "$ROOT"/../L02-*/L02-*/scripts/verify.sh
do
  [ -f "$f" ] && L02_VERIFY="$f" && break
done
if [ -n "$L02_VERIFY" ] && bash "$L02_VERIFY" >/dev/null 2>&1; then
  pass "L02 exposure audit green"
elif command -v openclaw >/dev/null 2>&1; then
  # Fallback: the built-in audit L02 builds on (also used when L02 verify is not green yet).
  if openclaw security audit >/dev/null 2>&1; then pass "L02 openclaw security audit ran"
  else fail "L02 openclaw security audit ran" "run: openclaw security audit"; fi
else
  fail "L02 exposure audit available" "complete Lesson 02 first"
fi

summary
[ "$FAIL_COUNT" -eq 0 ]
