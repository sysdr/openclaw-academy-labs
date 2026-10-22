#!/usr/bin/env bash
# Integration test with the real OpenClaw image. Skipped (exit 0) when Docker
# or the pinned image is absent. Runs in a throwaway copy on port 18799 so
# it never touches your own gateway or state/.
#   before setup: 8/10 (the Lesson 01 baseline fails OpenClaw's own audit)
#   after setup:  10/10
#   drift (mDNS full): 9/10, then restored: 10/10
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(grep -E '^OPENCLAW_VERSION=' "$ROOT/.env.example" | cut -d= -f2)"
if ! docker info >/dev/null 2>&1 || ! docker image inspect "ghcr.io/openclaw/openclaw:$VERSION" >/dev/null 2>&1; then
  echo "INTEGRATION SKIPPED (no Docker daemon or image ghcr.io/openclaw/openclaw:$VERSION)"
  exit 0
fi

TMP="$(mktemp -d)"
W="$TMP/lesson"
mkdir -p "$W"
cp -R "$ROOT/scripts" "$ROOT/src" "$ROOT/docker" "$ROOT/config" "$ROOT/.env.example" "$ROOT/.gitignore" "$W/"
printf 'OPENCLAW_VERSION=%s\nOPENCLAW_GATEWAY_PORT=18799\n' "$VERSION" > "$W/.env"
export COMPOSE_PROJECT_NAME="openclaw-l02-it-$$"
cleanup() {
  docker compose -f "$W/docker/compose.yaml" --env-file "$W/.env" down -v >/dev/null 2>&1 || true
  # state/ is owned by the container user; remove it from inside a container if needed.
  rm -rf "$TMP" 2>/dev/null || docker run --rm -v "$TMP:/t" "ghcr.io/openclaw/openclaw:$VERSION" sh -c 'rm -rf /t/lesson' >/dev/null 2>&1 || true
}
trap cleanup EXIT

expect() {  # expect "N/10 PASS" label
  local want="$1" label="$2" got
  got="$( { "$W/scripts/audit.sh" 2>/dev/null || true; } | tail -n 1)"
  if [ "$got" = "$want" ]; then printf '%-44s PASS (%s)\n' "$label" "$got"
  else printf '%-44s FAIL (got %s, want %s)\n' "$label" "$got" "$want"; exit 1; fi
}

"$W/scripts/bootstrap.sh" >/dev/null
"$W/scripts/run.sh" >/dev/null
expect "8/10 PASS"  "Lesson 01 baseline audit"
"$W/scripts/setup.sh" >/dev/null
expect "10/10 PASS" "after make setup"
"$W/scripts/verify.sh" >/dev/null && printf '%-44s PASS\n' "verify.sh exits 0 after setup"
docker compose -f "$W/docker/compose.yaml" --env-file "$W/.env" exec -T openclaw-gateway \
  node dist/index.js config set discovery.mdns.mode full >/dev/null
expect "9/10 PASS"  "drift: discovery.mdns.mode=full"
docker compose -f "$W/docker/compose.yaml" --env-file "$W/.env" exec -T openclaw-gateway \
  node dist/index.js config set discovery.mdns.mode off >/dev/null
expect "10/10 PASS" "drift restored"
echo "INTEGRATION PASS"
