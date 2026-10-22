#!/usr/bin/env bash
# Shared helpers for Lesson 02 scripts. Sourced, never run directly.
# shellcheck disable=SC2034  # variables are used by the scripts that source this
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
COMPOSE_FILE="$ROOT/docker/compose.yaml"
SERVICE="openclaw-gateway"
PASSES=0
FAILS=0

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found. Fix: $2"; }

# Load .env without executing it (values may contain shell metacharacters).
load_env() {
  [ -f "$ENV_FILE" ] || die ".env missing. Fix: make bootstrap"
  while IFS='=' read -r key value; do
    case "$key" in ''|\#*) continue ;; esac
    export "$key=$value"
  done < "$ENV_FILE"
  export STATE_DIR="${STATE_DIR:-$ROOT/state}"
  case "$STATE_DIR" in /*) ;; *) die "STATE_DIR in .env must be an absolute path" ;; esac
}

compose() { docker compose --progress quiet -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }
# Run the OpenClaw CLI inside the running gateway container.
oc() { compose exec -T "$SERVICE" node dist/index.js "$@"; }
# Same, but works whether or not the gateway is up. OpenClaw refuses config
# writes from a second PID namespace while the gateway holds its lock, so a
# running gateway must be reached with exec, not a one-off run.
oc_any() {
  if [ -n "$(compose ps -q "$SERVICE" 2>/dev/null)" ]; then oc "$@"
  else compose run --rm --no-deps -T "$SERVICE" node dist/index.js "$@"; fi
}

# Portable file mode (GNU stat, BSD stat and python all differ; python is a prerequisite).
file_mode() {
  if [ -e "$1" ]; then
    python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])' "$1"
  else
    echo missing
  fi
}

random_hex() { python3 -c 'import secrets; print(secrets.token_hex(32))'; }

# check "description" command... -> one line ending PASS/FAIL
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '%-52s PASS\n' "$desc"; PASSES=$((PASSES + 1))
  else
    printf '%-52s FAIL\n' "$desc"; FAILS=$((FAILS + 1))
  fi
}

summary() {
  local total=$((PASSES + FAILS))
  echo "$PASSES/$total PASS"
  [ "$FAILS" -eq 0 ]
}

# HTTP status of a URL, with curl or a python fallback.
http_status() {
  if command -v curl >/dev/null 2>&1; then
    curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$1" || echo 000
  else
    python3 - "$1" <<'PY'
import sys, urllib.request, urllib.error
try:
    print(urllib.request.urlopen(sys.argv[1], timeout=3).status)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception:
    print("000")
PY
  fi
}
