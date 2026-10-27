#!/usr/bin/env bash
# Stop L04 local services and reclaim unused Docker resources
# (containers, networks, dangling images). Safe to rerun.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "== Lesson 04 cleanup =="

echo "-- Stopping OpenClaw gateway / probe (if any)"
pkill -f 'openclaw.*gateway' 2>/dev/null || true
pkill -f 'probe_model.py' 2>/dev/null || true
if [ -f "$ROOT/.state/probe.pid" ]; then
  kill "$(cat "$ROOT/.state/probe.pid")" 2>/dev/null || true
  rm -f "$ROOT/.state/probe.pid"
fi
if [ -f "$HOME/.openclaw/gateway-l04.pid" ]; then
  kill "$(cat "$HOME/.openclaw/gateway-l04.pid")" 2>/dev/null || true
  rm -f "$HOME/.openclaw/gateway-l04.pid"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI not found; skip container cleanup."
else
  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon not reachable; skip container stop."
  else
    echo "-- Stopping all running containers"
    ids="$(docker ps -q 2>/dev/null || true)"
    if [ -n "$ids" ]; then
      # shellcheck disable=SC2086
      docker stop $ids >/dev/null 2>&1 || true
    fi

    echo "-- Removing stopped containers"
    docker container prune -f >/dev/null 2>&1 || true

    echo "-- Pruning unused networks and dangling images"
    docker network prune -f >/dev/null 2>&1 || true
    docker image prune -f >/dev/null 2>&1 || true

    # Optional: remove OpenClaw lesson images if present
    for IMAGE in \
      "ghcr.io/openclaw/openclaw:2026.10.4" \
      "ghcr.io/openclaw/openclaw:2026.10.7" \
      "ghcr.io/openclaw/openclaw:latest"
    do
      if docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "-- Removing image $IMAGE"
        docker rmi "$IMAGE" 2>/dev/null || true
      fi
    done
  fi
fi

echo "-- Removing local secrets and runtime junk (not for git)"
rm -rf "$ROOT/.state" "$ROOT/reports" \
  "$ROOT/src/__pycache__" "$ROOT/tests/__pycache__" \
  "$ROOT"/.pytest_cache 2>/dev/null || true
if [ -f "$ROOT/.env" ]; then
  rm -f "$ROOT/.env"
  echo "   deleted .env (gateway token / secrets)"
fi

echo "== Cleanup done =="
echo "Kept source files. Recreate secrets from .env.example when you run again."
