#!/usr/bin/env bash
# build: make sure the pinned image is present and the compose file is valid.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need docker "install Docker: https://docs.docker.com/get-docker/"
load_env
image="ghcr.io/openclaw/openclaw:$OPENCLAW_VERSION"
docker image inspect "$image" >/dev/null 2>&1 || docker pull "$image"
compose config --quiet && echo "docker/compose.yaml is valid"
docker run --rm "$image" node dist/index.js --version
