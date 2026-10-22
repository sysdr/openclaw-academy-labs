#!/usr/bin/env bash
# run: start the gateway (idempotent) and wait until Docker reports it healthy.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need docker "install Docker: https://docs.docker.com/get-docker/"
load_env
compose up -d "$SERVICE" >/dev/null
cid="$(compose ps -q "$SERVICE")"
# Slow hosts (WSL + Docker Desktop) often need 60–90s for first boot / SQLite maintenance.
for _ in $(seq 1 90); do
  status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || echo gone)"
  case "$status" in
    healthy) echo "Gateway healthy on 127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}. Next: make verify"; exit 0 ;;
    gone) break ;;
    # Keep waiting through temporary unhealthy during start; only fail after the loop.
  esac
  sleep 2
done
status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || echo gone)"
if [ "$status" = healthy ]; then
  echo "Gateway healthy on 127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}. Next: make verify"
  exit 0
fi
echo "Gateway did not become healthy (status: ${status:-unknown}). Last log lines:" >&2
compose logs --tail 20 "$SERVICE" >&2 || true
exit 1
