#!/usr/bin/env bash
# cleanup: remove local-only files (not for git push), wipe secrets, stop the
# lesson gateway, and prune unused Docker resources. Non-interactive.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$ROOT/scripts/lib.sh"

echo "==> Stopping Lesson 02 containers"
if [ -f "$ENV_FILE" ]; then
  # load_env needs a readable .env; tolerate a broken one for teardown
  set +e
  load_env 2>/dev/null
  set -e
fi
if [ -f "$COMPOSE_FILE" ]; then
  docker compose --progress quiet -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down --remove-orphans >/dev/null 2>&1 \
    || docker compose --progress quiet -f "$COMPOSE_FILE" down --remove-orphans >/dev/null 2>&1 \
    || true
fi
# Also stop if the project name is still around without .env
docker compose -p openclaw-l02 down --remove-orphans >/dev/null 2>&1 || true
echo "    Gateway stopped (if it was running)."

echo "==> Removing local-only paths (gitignored / not for push)"
rm -rf -- \
  "$ROOT/state" \
  "$ROOT/reports" \
  "$ROOT/__pycache__" \
  "$ROOT/.pytest_cache" \
  "$ROOT/src/__pycache__" \
  "$ROOT/tests/__pycache__"
find "$ROOT" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
find "$ROOT" -type f \( -name '*.pyc' -o -name '.DS_Store' -o -name '*~' \) -delete 2>/dev/null || true

echo "==> Removing secrets (.env with gateway token)"
rm -f -- "$ENV_FILE"
# Ensure .env.example has no real token (placeholders only)
if [ -f "$ROOT/.env.example" ]; then
  # rewrite token/uid/gid lines empty if someone pasted secrets into the example
  tmp="$(mktemp)"
  sed -E \
    -e 's/^(OPENCLAW_GATEWAY_TOKEN)=.+/\1=/' \
    -e 's/^(OPENCLAW_UID)=.+/\1=/' \
    -e 's/^(OPENCLAW_GID)=.+/\1=/' \
    "$ROOT/.env.example" > "$tmp"
  mv "$tmp" "$ROOT/.env.example"
fi
echo "    Removed .env; .env.example left as placeholders only."

echo "==> Pruning unused Docker resources"
if docker info >/dev/null 2>&1; then
  docker container prune -f >/dev/null
  docker network prune -f >/dev/null
  docker volume prune -f >/dev/null
  # Remove images not used by any container (includes unused openclaw pin)
  docker image prune -af >/dev/null
  echo "    Containers, networks, volumes, and unused images pruned."
else
  echo "    Docker daemon not reachable; skipped Docker prune."
fi

echo "==> Done. Safe to git add/commit/push (no .env, state/, or reports/)."
echo "    Recreate later with: make bootstrap && make build && make run"
