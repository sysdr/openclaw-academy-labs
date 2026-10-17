#!/usr/bin/env bash
# Shared helpers for Lesson 01 scripts. Source it; do not run it.
# shellcheck disable=SC2034  # variables are used by the scripts that source this file

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/docker/compose.yaml"
ENV_FILE="${L01_ENV_FILE:-$ROOT/.env}"
STATE_DIR="${L01_STATE_DIR:-$ROOT/state}"
PINNED_IMAGE="ghcr.io/openclaw/openclaw:2026.10.4"
PASS_COUNT=0
FAIL_COUNT=0

# Load .env without executing it as shell code (KEY=VALUE lines only).
load_env() {
  [ -f "$ENV_FILE" ] || return 0
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    key="${line%%=*}"; val="${line#*=}"
    case "$key" in *[!A-Za-z0-9_]*|'') continue ;; esac
    if [ -z "${!key:-}" ]; then export "$key=$val"; fi
  done < "$ENV_FILE"
}

compose() {
  local extra=()
  # Integration tests add an overlay file (tests/compose.fake-llm.yaml).
  if [ -n "${L01_COMPOSE_EXTRA:-}" ]; then extra=(-f "$L01_COMPOSE_EXTRA"); fi
  docker compose --project-directory "$ROOT" -f "$COMPOSE_FILE" "${extra[@]+"${extra[@]}"}" \
    --env-file "$ENV_FILE" "$@"
}

gateway_running() {
  [ -n "$(compose ps -q --status running openclaw-gateway 2>/dev/null)" ]
}

# oc <args>: run the OpenClaw CLI. Inside the running Gateway container when it
# is up (same PID namespace, so ownership checks pass); otherwise as a one-shot
# container with no Gateway (used during setup).
oc() {
  if gateway_running; then
    compose exec -T openclaw-gateway node dist/index.js "$@"
  else
    compose run -T --rm --no-deps --entrypoint node openclaw-gateway dist/index.js "$@"
  fi
}

# check "description" command...   -> prints one PASS/FAIL line, never exits
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '%-58s PASS\n' "$desc"; PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf '%-58s FAIL\n' "$desc"; FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

summary() {
  local total=$((PASS_COUNT + FAIL_COUNT))
  if [ "$FAIL_COUNT" -eq 0 ]; then echo "$PASS_COUNT/$total PASS"; else echo "$PASS_COUNT/$total PASS ($FAIL_COUNT FAIL)"; fi
  [ "$FAIL_COUNT" -eq 0 ]
}

die() { echo "ERROR: $*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found. Fix: $2"
}

random_hex() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex 32
  else python3 -c 'import secrets; print(secrets.token_hex(32))'; fi
}

# HTTP status code of a URL (curl, falling back to python3). Prints 000 on error.
http_code() {
  if command -v curl >/dev/null 2>&1; then
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$1" || true)"
    echo "${code:-000}"
  else
    python3 - "$1" <<'PY'
import sys, urllib.request, urllib.error
try:
    print(urllib.request.urlopen(sys.argv[1], timeout=5).status)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception:
    print("000")
PY
  fi
}

# Wait until /startupz returns 200 (traffic admission), not just /healthz.
wait_ready() {
  local port="${OPENCLAW_GATEWAY_PORT:-18789}" tries="${1:-60}" code
  for _ in $(seq 1 "$tries"); do
    code="$(http_code "http://127.0.0.1:$port/startupz")"
    [ "$code" = "200" ] && return 0
    sleep 2
  done
  return 1
}

# Wait until Docker's own healthcheck says "healthy" (first probe can take 30s).
wait_healthy() {
  local tries="${1:-45}" cid status
  cid="$(compose ps -q openclaw-gateway 2>/dev/null | head -n 1)"
  [ -n "$cid" ] || return 1
  for _ in $(seq 1 "$tries"); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid" 2>/dev/null || true)"
    [ "$status" = "healthy" ] && return 0
    sleep 2
  done
  return 1
}
