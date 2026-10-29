#!/usr/bin/env bash
# Stop local L05 services and reclaim unused Docker resources.
# Safe for git: does not delete source files; only runtime/cache/Docker leftovers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "== L05 cleanup =="

# --- OpenClaw gateway + skill probe ---
if command -v openclaw >/dev/null 2>&1; then
  echo "[1/5] Stopping OpenClaw gateway (if running)..."
  openclaw gateway stop --force >/dev/null 2>&1 || openclaw gateway stop >/dev/null 2>&1 || true
else
  echo "[1/5] openclaw not found; skipping gateway stop"
fi

echo "[2/5] Stopping skill probe on :18999 (if running)..."
if [ -f "$ROOT/.state/probe.pid" ]; then
  kill "$(cat "$ROOT/.state/probe.pid")" 2>/dev/null || true
  rm -f "$ROOT/.state/probe.pid"
fi
pkill -f 'probe_model.py' 2>/dev/null || true
# Free the port if something else still holds it
if command -v ss >/dev/null 2>&1; then
  for port in 18999 18789; do
    pids=$(ss -ltnp 2>/dev/null | awk -v p=":$port" '$4 ~ p {print}' | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)
    for pid in $pids; do
      # Only kill openclaw-gateway / probe_model, not unrelated listeners
      cmd=$(ps -p "$pid" -o args= 2>/dev/null || true)
      case "$cmd" in
        *openclaw*|*probe_model*) kill "$pid" 2>/dev/null || true ;;
      esac
    done
  done
fi

# --- Lesson local artifacts (not for git push) ---
echo "[3/5] Removing local runtime artifacts..."
rm -rf "$ROOT/.state" "$ROOT/reports" \
  "$ROOT"/src/__pycache__ "$ROOT"/tests/__pycache__ \
  "$ROOT"/.pytest_cache "$ROOT"/.mypy_cache "$ROOT"/.ruff_cache
find "$ROOT" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
find "$ROOT" -type f \( -name '*.pyc' -o -name '*.pyo' -o -name '.DS_Store' \) -delete 2>/dev/null || true
# Never commit a real .env; drop it if present (keep .env.example)
if [ -f "$ROOT/.env" ]; then
  echo "       Removing .env (secrets stay out of git)"
  rm -f "$ROOT/.env"
fi

# --- Docker ---
echo "[4/5] Stopping containers and pruning unused Docker resources..."
if ! command -v docker >/dev/null 2>&1; then
  echo "       docker not found; skipping"
else
  if ! docker info >/dev/null 2>&1; then
    echo "       docker daemon not reachable; skipping prune"
  else
    # Stop & remove all containers (none expected for this lesson; reclaim anyway)
    ids=$(docker ps -aq 2>/dev/null || true)
    if [ -n "${ids:-}" ]; then
      docker stop $ids >/dev/null 2>&1 || true
      docker rm -f $ids >/dev/null 2>&1 || true
      echo "       removed containers"
    else
      echo "       no containers"
    fi
    # Unused images, networks, build cache, dangling volumes
    docker container prune -f >/dev/null 2>&1 || true
    docker image prune -af >/dev/null 2>&1 || true
    docker network prune -f >/dev/null 2>&1 || true
    docker volume prune -f >/dev/null 2>&1 || true
    docker builder prune -af >/dev/null 2>&1 || true
    echo "       pruned unused images/networks/volumes/build cache"
  fi
fi

echo "[5/5] Done."
echo "Gateway/probe stopped; local junk removed; Docker unused resources pruned."
echo "Source tree kept. .gitignore ignores .env, .state/, reports/, caches."
