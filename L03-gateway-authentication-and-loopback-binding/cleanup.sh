#!/usr/bin/env bash
# cleanup: remove local-only files (not for git push), wipe secrets, stop the
# Gateway (native or Docker), and prune unused Docker resources. Non-interactive.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "== Lesson 03 cleanup =="

echo "==> Stopping native Gateway (if running)"
if command -v openclaw >/dev/null 2>&1; then
  openclaw gateway stop >/dev/null 2>&1 || true
fi
# Foreground `make run` / stray listeners on the lesson port
if command -v lsof >/dev/null 2>&1; then
  pids="$(lsof -t -nP -iTCP:18789 -sTCP:LISTEN 2>/dev/null || true)"
  if [ -n "${pids:-}" ]; then
    # shellcheck disable=SC2086
    kill $pids >/dev/null 2>&1 || true
    sleep 1
    # shellcheck disable=SC2086
    kill -9 $pids >/dev/null 2>&1 || true
  fi
fi
echo "    Native Gateway stopped (if it was running)."

echo "==> Stopping Docker compose (loopback override / L01 base, if present)"
docker_ok() { command -v docker >/dev/null 2>&1 && timeout 15 docker info >/dev/null 2>&1; }
run_docker() { timeout 60 docker "$@" >/dev/null 2>&1 || true; }
if docker_ok; then
  LOOPBACK="$ROOT/docker/compose.loopback.yml"
  # Common layouts: this lesson only, or paired with L01's compose next door.
  for base in \
    "$ROOT/docker/compose.yaml" \
    "$ROOT/../L01-install-openclaw-2-0-inside-a-sandbox/docker/compose.yaml" \
    "$ROOT/docker-compose.yml"
  do
    if [ -f "$base" ] && [ -f "$LOOPBACK" ]; then
      timeout 60 docker compose --project-directory "$(dirname "$base")/.." \
        -f "$base" -f "$LOOPBACK" down --remove-orphans >/dev/null 2>&1 || true
    elif [ -f "$base" ]; then
      timeout 60 docker compose --project-directory "$(dirname "$base")/.." \
        -f "$base" down --remove-orphans >/dev/null 2>&1 || true
    fi
  done
  run_docker compose -p openclaw-l03 down --remove-orphans
  run_docker compose -f "$LOOPBACK" down --remove-orphans

  echo "    Removing leftover openclaw* lesson containers"
  ids="$(timeout 30 docker ps -aq --filter "name=openclaw" 2>/dev/null || true)"
  if [ -n "${ids:-}" ]; then
    # shellcheck disable=SC2086
    timeout 60 docker rm -f $ids >/dev/null 2>&1 || true
  fi

  echo "==> Pruning unused Docker resources"
  run_docker container prune -f
  run_docker network prune -f
  run_docker volume prune -f
  run_docker image prune -af
  echo "    Containers, networks, volumes, and unused images pruned."
else
  echo "    Docker not available; skipped compose stop and prune."
fi

echo "==> Removing local-only paths (gitignored / not for push)"
rm -rf -- \
  "$ROOT/reports" \
  "$ROOT/__pycache__" \
  "$ROOT/.pytest_cache" \
  "$ROOT/src/__pycache__" \
  "$ROOT/tests/__pycache__" \
  "$ROOT/solution/__pycache__"
find "$ROOT" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
find "$ROOT" -type f \( -name '*.pyc' -o -name '.DS_Store' -o -name '*~' \) -delete 2>/dev/null || true

echo "==> Removing secrets (.env with gateway token)"
if [ -f "$ROOT/.env" ]; then
  rm -f -- "$ROOT/.env"
  echo "    deleted .env (gateway token)"
fi
# Keep .env.example as placeholders only (never real secrets).
if [ -f "$ROOT/.env.example" ]; then
  tmp="$(mktemp)"
  sed -E 's/^(OPENCLAW_GATEWAY_TOKEN)=.+/\1=replace-with-64-hex-chars/' \
    "$ROOT/.env.example" > "$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$ROOT/.env.example"
fi
echo "    .env.example left as placeholders only."

echo "==> Done. Safe to git add/commit/push (no .env or reports/)."
echo "    Recreate later with: make bootstrap && make setup && make run"
