#!/usr/bin/env bash
# setup: close what the 'before' audit finds. Applies the Lesson 02 config
# patch in one validated write, then makes secrets and state owner-only.
# Safe to rerun: the patch is a merge, chmod is idempotent.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need docker "install Docker: https://docs.docker.com/get-docker/"
load_env
[ -f "$STATE_DIR/openclaw/openclaw.json" ] || die "no OpenClaw state yet. Fix: make bootstrap"

echo "Applying config/l02-hardening.patch.json5"
# Capture patch output: OpenClaw often applies these keys live ("No gateway
# restart needed"). A forced restart + health wait is the multi-minute cost
# on slow hosts (WSL / Docker Desktop), so only restart when OpenClaw asks.
patch_out="$(mktemp)"
# `config patch` validates on write; a second `config validate` doubles the
# ~1–2 min CLI cost on slow hosts, so we skip it after a successful patch.
oc_any config patch --stdin < "$ROOT/config/l02-hardening.patch.json5" | tee "$patch_out"

echo "Tightening file modes"
chmod 600 "$ENV_FILE"
chmod 700 "$STATE_DIR/openclaw"
chmod 600 "$STATE_DIR/openclaw/openclaw.json"
grep -qxE '/?\.env' "$ROOT/.gitignore" 2>/dev/null || echo ".env" >> "$ROOT/.gitignore"

need_restart=0
if grep -qiE 'restart (the )?gateway|gateway restart required|please restart' "$patch_out" \
  && ! grep -qiE 'no gateway restart needed|restart not (required|needed)' "$patch_out"; then
  need_restart=1
fi
rm -f "$patch_out"

if [ "$need_restart" = 1 ] && [ -n "$(compose ps -q "$SERVICE" 2>/dev/null)" ]; then
  echo "Restarting the gateway so it serves the new config"
  compose restart "$SERVICE" >/dev/null
  "$ROOT/scripts/run.sh"
else
  echo "Skipping gateway restart (config already live or gateway not running)"
fi
echo "Done. Next: make verify"
