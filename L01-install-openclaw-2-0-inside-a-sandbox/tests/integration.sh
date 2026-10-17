#!/usr/bin/env bash
# Integration test: the real OpenClaw image, the real Lesson 01 compose file,
# the real setup/run/verify scripts, and an offline fake model. Uses its own
# project name, port, .env and state dir, so your lesson setup is untouched.
# Skips (exit 0) when Docker or the OpenClaw image is not available.
set -euo pipefail
LESSON="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:2026.10.4}"

if ! docker info >/dev/null 2>&1; then echo "SKIP integration: Docker not reachable"; exit 0; fi
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "SKIP integration: image $IMAGE not present (run make build first)"; exit 0
fi
if [ "$(uname -s)" = "Linux" ] && [ "$(id -u)" != "0" ] && [ "$(id -u)" != "1000" ]; then
  echo "SKIP integration: Linux uid $(id -u) cannot hand a state dir to container uid 1000"; exit 0
fi

WORK="${IT_WORK:-$(mktemp -d)}"; mkdir -p "$WORK"
export L01_ENV_FILE="$WORK/.env" L01_STATE_DIR="$WORK/state"
export COMPOSE_PROJECT_NAME="openclaw-l01-it" OPENCLAW_GATEWAY_PORT="${IT_PORT:-18799}"
export L01_COMPOSE_EXTRA="$LESSON/tests/compose.fake-llm.yaml" OPENCLAW_IMAGE="$IMAGE"
cleanup() {
  (cd "$LESSON" && . scripts/lib.sh && compose down -v --remove-orphans >/dev/null 2>&1) || true
  rm -rf "$WORK" 2>/dev/null || true
}
[ "${IT_KEEP:-0}" = 1 ] || trap cleanup EXIT

cat > "$L01_ENV_FILE" <<EOF
OPENCLAW_IMAGE=$IMAGE
OPENCLAW_GATEWAY_PORT=$OPENCLAW_GATEWAY_PORT
OPENCLAW_AUTH_CHOICE=custom-api-key
CUSTOM_API_KEY=offline-test-key
EOF
mkdir -p "$L01_STATE_DIR/openclaw/workspace" "$L01_STATE_DIR/auth-profile-secrets"
if [ "$(uname -s)" = "Linux" ] && [ "$(id -u)" = "0" ]; then chown -R 1000:1000 "$L01_STATE_DIR"; fi

(cd "$LESSON" && . scripts/lib.sh && compose up -d fake-llm >/dev/null)
bash "$LESSON/scripts/setup.sh" --custom-base-url http://fake-llm:18800/v1 \
  --custom-model-id fake-model --custom-compatibility openai --custom-text-input
bash "$LESSON/scripts/run.sh"
out="$(bash "$LESSON/scripts/verify.sh" || true)"
echo "$out"
if echo "$out" | grep -Eq '^([0-9]+)/\1 PASS$'; then
  echo "INTEGRATION PASS"
else
  echo "INTEGRATION FAIL"; exit 1
fi
