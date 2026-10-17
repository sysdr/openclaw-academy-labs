#!/usr/bin/env bash
# build: pull the pinned image (no source build needed) and validate compose.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need docker "install Docker: https://docs.docker.com/get-docker/"
[ -f "$ENV_FILE" ] || cp "$ROOT/.env.example" "$ENV_FILE"
load_env
IMAGE="${OPENCLAW_IMAGE:-$PINNED_IMAGE}"

if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Image present: $IMAGE"
else
  echo "Pulling $IMAGE ..."
  docker pull "$IMAGE"
fi
compose config --quiet && echo "docker/compose.yaml is valid"
echo "Image digest (record it in your notes):"
docker image inspect --format '{{join .RepoDigests "\n"}}' "$IMAGE" 2>/dev/null || true
docker run --rm --entrypoint node "$IMAGE" dist/index.js --version
