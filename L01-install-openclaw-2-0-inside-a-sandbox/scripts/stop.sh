#!/usr/bin/env bash
# stop: shut down every Lesson 01 Docker service (Gateway, fake-llm overlay,
# leftover integration project). Does not delete state/ or .env, and does not
# stop the Docker daemon.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

need docker "install Docker: https://docs.docker.com/get-docker/"

echo "Stopping Lesson 01 Docker services..."

# Main project (with fake-llm overlay if that compose file exists).
if [ -f "$ENV_FILE" ]; then
  if [ -f "$ROOT/tests/compose.fake-llm.yaml" ]; then
    L01_COMPOSE_EXTRA="$ROOT/tests/compose.fake-llm.yaml" compose down --remove-orphans 2>/dev/null || true
  fi
  compose down --remove-orphans 2>/dev/null || true
else
  docker compose --project-directory "$ROOT" -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
fi

# Integration test project (tests/integration.sh), if still running.
docker compose -p openclaw-l01-it --project-directory "$ROOT" -f "$COMPOSE_FILE" \
  -f "$ROOT/tests/compose.fake-llm.yaml" down --remove-orphans -v 2>/dev/null || true

# Any leftover containers that still match this lesson's name prefix.
ids="$(docker ps -aq --filter "name=openclaw-l01" 2>/dev/null || true)"
if [ -n "$ids" ]; then
  # shellcheck disable=SC2086
  docker rm -f $ids >/dev/null 2>&1 || true
fi

echo "Lesson 01 services stopped."
docker ps --filter "name=openclaw-l01" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
echo "State and .env kept. To remove them too: make clean"
