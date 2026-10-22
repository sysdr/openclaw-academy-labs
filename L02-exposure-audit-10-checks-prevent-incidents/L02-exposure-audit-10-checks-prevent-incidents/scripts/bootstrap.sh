#!/usr/bin/env bash
# bootstrap: host prerequisites, then recreate Lesson 01's end state for
# readers who skipped it: .env with a gateway token, private state/, token
# auth, and Lesson 01's exec policy (deny). No model key is needed: the
# audit inspects configuration, it never sends a prompt.
# Safe to rerun: existing .env and state/ are kept.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

echo "Lesson 02 bootstrap: prerequisites"
check "docker CLI installed"            command -v docker
check "Docker daemon reachable"         docker info
check "Docker Compose v2 available"     docker compose version
check "python3 is 3.11 or newer"        python3 -c 'import sys; assert sys.version_info >= (3, 11)'
if ! summary; then
  echo "Fix: install Docker Desktop or Docker Engine + Compose v2 (https://docs.docker.com/get-docker/)"
  echo "and Python 3.11+, start Docker, then rerun make bootstrap."
  exit 1
fi

# .env (from Lesson 01): generated token, container UID, version pin.
if [ ! -f "$ENV_FILE" ]; then
  cp "$ROOT/.env.example" "$ENV_FILE"
  echo "Created .env from .env.example"
fi
set_env() {  # set_env KEY VALUE, only when KEY is missing or empty
  if ! grep -Eq "^$1=.+" "$ENV_FILE"; then
    local tmp; tmp="$(mktemp)"
    grep -v "^$1=" "$ENV_FILE" > "$tmp" || true
    echo "$1=$2" >> "$tmp"
    mv "$tmp" "$ENV_FILE"
  fi
}
uid="$(id -u)"; gid="$(id -g)"
# A root host user would make the container run as root; use the image's node user instead.
if [ "$uid" = "0" ]; then uid=1000; gid=1000; fi
set_env OPENCLAW_GATEWAY_TOKEN "$(random_hex)"
set_env OPENCLAW_UID "$uid"
set_env OPENCLAW_GID "$gid"
chmod 600 "$ENV_FILE"
load_env

mkdir -p "$STATE_DIR/openclaw" "$ROOT/reports"
if [ "$(id -u)" = "0" ]; then chown -R "$uid:$gid" "$STATE_DIR"; fi

docker image inspect "ghcr.io/openclaw/openclaw:$OPENCLAW_VERSION" >/dev/null 2>&1 \
  || docker pull "ghcr.io/openclaw/openclaw:$OPENCLAW_VERSION"

if [ ! -f "$STATE_DIR/openclaw/openclaw.json" ]; then
  echo "No Lesson 01 state found: creating the Lesson 01 baseline (no model configured)"
  oc_any config set gateway.mode local >/dev/null
  oc_any config set gateway.bind lan >/dev/null      # Lesson 01: listener inside the container
  oc_any config set gateway.auth.mode token >/dev/null # token comes from OPENCLAW_GATEWAY_TOKEN
  oc_any approvals set --stdin < "$ROOT/config/exec-approvals.json" >/dev/null
  echo "Lesson 01 baseline ready."
else
  echo "Found existing state in ${STATE_DIR#"$ROOT"/}; keeping it."
fi
echo "Next: make build && make run, then make verify to see the 'before' audit."
