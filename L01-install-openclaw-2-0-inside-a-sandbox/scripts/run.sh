#!/usr/bin/env bash
# run: start the Gateway container and wait for traffic admission (/startupz).
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need docker "install Docker: https://docs.docker.com/get-docker/"
[ -f "$ENV_FILE" ] || die ".env missing. Run: make setup"
[ -f "$STATE_DIR/openclaw/openclaw.json" ] || die "not onboarded yet. Run: make setup"
load_env

compose up -d openclaw-gateway
echo "Waiting for http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}/startupz ..."
if wait_ready 60 && wait_healthy 45; then
  echo "Gateway is admitting traffic and Docker reports it healthy. Next: make verify"
else
  echo "Gateway did not become ready and healthy in time. Last log lines:"
  compose logs --tail 30 openclaw-gateway || true
  exit 1
fi
