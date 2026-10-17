#!/usr/bin/env bash
# setup: create .env with a fresh gateway token, then run OpenClaw's headless
# onboarding inside the container. Safe to rerun: existing values are kept.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need docker "install Docker: https://docs.docker.com/get-docker/"

if [ ! -f "$ENV_FILE" ]; then
  cp "$ROOT/.env.example" "$ENV_FILE"
  echo "Created .env from .env.example"
fi
chmod 600 "$ENV_FILE"

# Gateway token: generate once, never print it.
if ! grep -Eq '^OPENCLAW_GATEWAY_TOKEN=.{32,}$' "$ENV_FILE"; then
  tmp="$(mktemp)"
  grep -v '^OPENCLAW_GATEWAY_TOKEN=' "$ENV_FILE" > "$tmp" || true
  echo "OPENCLAW_GATEWAY_TOKEN=$(random_hex)" >> "$tmp"
  mv "$tmp" "$ENV_FILE"; chmod 600 "$ENV_FILE"
  echo "Generated OPENCLAW_GATEWAY_TOKEN in .env (not shown)"
fi
load_env

AUTH_CHOICE="${OPENCLAW_AUTH_CHOICE:-gemini-api-key}"
# Google AI Studio accepts GEMINI_API_KEY or GOOGLE_API_KEY; prefer GEMINI for the secret ref.
if [ "$AUTH_CHOICE" = "gemini-api-key" ]; then
  if [ -z "${GEMINI_API_KEY:-}" ] && [ -n "${GOOGLE_API_KEY:-}" ]; then
    export GEMINI_API_KEY="$GOOGLE_API_KEY"
  fi
  if [ -z "${GEMINI_API_KEY:-}" ]; then
    die "GEMINI_API_KEY is empty. Put your Google AI Studio key in .env (or set GOOGLE_API_KEY), then rerun make setup."
  fi
elif [ "$AUTH_CHOICE" = "openai-api-key" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
  die "OPENAI_API_KEY is empty. Put your provider key in .env (it stays on this machine), then rerun make setup."
fi

mkdir -p "$STATE_DIR/openclaw/workspace" "$STATE_DIR/auth-profile-secrets"
chmod 700 "$STATE_DIR" "$STATE_DIR/openclaw" "$STATE_DIR/auth-profile-secrets" 2>/dev/null || true
# The image runs as user "node" (uid 1000). On Linux, bind-mounted dirs keep
# host ownership, so a different host uid means the Gateway cannot write state.
if [ "$(uname -s)" = "Linux" ] && [ "$(stat -c %u "$STATE_DIR/openclaw")" != "1000" ]; then
  echo "state/ is not owned by uid 1000, so the container user cannot write it."
  echo "Fix (needs sudo once, changes only this lesson folder):"
  echo "  sudo chown -R 1000:1000 \"$STATE_DIR\""
  exit 1
fi

if [ -f "$STATE_DIR/openclaw/openclaw.json" ]; then
  echo "Onboarding already done (state/openclaw/openclaw.json exists); skipping."
else
  echo "Running headless onboarding inside the container..."
  # --accept-risk is required for --non-interactive. It acknowledges the agent
  # can act on its host; the container is that host, which is why we accept it.
  oc onboard --non-interactive --accept-risk --skip-health \
    --mode local --auth-choice "$AUTH_CHOICE" --secret-input-mode ref \
    --gateway-auth token --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
    --gateway-bind lan --skip-channels --no-install-daemon \
    "$@"
fi

echo "Applying config/exec-approvals.json5 (exec denied by default)..."
oc approvals set --stdin < "$ROOT/config/exec-approvals.json5" >/dev/null

# Google onboard defaults to gemini-*-pro-preview, which often 429s on free/AI Studio
# quotas. New AI Studio keys also reject older flash IDs (404). Pin the current
# Flash model Google recommends for new users so make verify can complete a turn.
if [ "$AUTH_CHOICE" = "gemini-api-key" ]; then
  echo "Pinning default model to google/gemini-3.8-flash..."
  oc models set google/gemini-3.8-flash >/dev/null
  oc models fallbacks add google/gemini-flash-latest >/dev/null 2>&1 || true
  oc models fallbacks add google/gemini-3.1-flash-lite >/dev/null 2>&1 || true
  oc config set memory.search.enabled false >/dev/null 2>&1 || true
fi

echo "Setup complete. Next: make run"
