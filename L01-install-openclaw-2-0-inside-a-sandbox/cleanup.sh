#!/usr/bin/env bash
# Stop Lesson 01 containers and reclaim unused Docker resources
# (containers, networks, dangling images). Safe to rerun.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "== Lesson 01 cleanup =="

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI not found; nothing to stop."
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon not reachable; skip container stop."
else
  COMPOSE_FILE="$ROOT/docker/compose.yaml"
  ENV_FILE="$ROOT/.env"
  EXTRA=()
  if [ -f "$ROOT/tests/compose.fake-llm.yaml" ]; then
    EXTRA=(-f "$ROOT/tests/compose.fake-llm.yaml")
  fi

  echo "-- Stopping compose project openclaw-l01"
  if [ -f "$ENV_FILE" ]; then
    docker compose --project-directory "$ROOT" -f "$COMPOSE_FILE" "${EXTRA[@]+"${EXTRA[@]}"}" \
      --env-file "$ENV_FILE" down --remove-orphans -v 2>/dev/null || true
  fi
  docker compose --project-directory "$ROOT" -f "$COMPOSE_FILE" \
    down --remove-orphans -v 2>/dev/null || true

  echo "-- Stopping integration project openclaw-l01-it (if any)"
  docker compose -p openclaw-l01-it --project-directory "$ROOT" -f "$COMPOSE_FILE" \
    "${EXTRA[@]+"${EXTRA[@]}"}" down --remove-orphans -v 2>/dev/null || true

  echo "-- Removing leftover openclaw-l01* containers"
  ids="$(docker ps -aq --filter "name=openclaw-l01" 2>/dev/null || true)"
  if [ -n "$ids" ]; then
    # shellcheck disable=SC2086
    docker rm -f $ids >/dev/null 2>&1 || true
  fi

  echo "-- Pruning unused containers, networks, dangling images"
  docker container prune -f >/dev/null 2>&1 || true
  docker network prune -f >/dev/null 2>&1 || true
  docker image prune -f >/dev/null 2>&1 || true

  # Remove the pinned lesson image if present (optional reclaim).
  IMAGE="ghcr.io/openclaw/openclaw:2026.10.4"
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "-- Removing lesson image $IMAGE"
    docker rmi "$IMAGE" 2>/dev/null || true
  fi
fi

echo "-- Removing local secrets and runtime junk (not for git)"
rm -rf "$ROOT/state" "$ROOT/reports" \
  "$ROOT/src/__pycache__" "$ROOT/tests/__pycache__" \
  "$ROOT"/.pytest_cache 2>/dev/null || true
if [ -f "$ROOT/.env" ]; then
  rm -f "$ROOT/.env"
  echo "   deleted .env (API keys / gateway token)"
fi

echo "== Cleanup done =="
docker ps --filter "name=openclaw-l01" --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || true
echo "Kept source files. Recreate secrets from .env.example when you run again."
