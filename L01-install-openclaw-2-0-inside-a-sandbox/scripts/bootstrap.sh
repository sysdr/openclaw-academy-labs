#!/usr/bin/env bash
# bootstrap: Lesson 01 has no previous lesson, so "recreate the previous end
# state" means: confirm the host can run the sandbox at all. Safe to rerun.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
load_env
PORT="${OPENCLAW_GATEWAY_PORT:-18789}"

port_free() {
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$PORT\$"; then return 1; fi
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then return 1; fi
  else
    python3 -c "import socket,sys; s=socket.socket(); s.bind(('127.0.0.1', int(sys.argv[1]))); s.close()" "$PORT"
  fi
}
# A port already held by THIS lesson's gateway is fine (rerun after `make run`).
port_ok() {
  port_free && return 0
  [ -f "$ENV_FILE" ] && gateway_running
}

echo "Lesson 01 bootstrap: host prerequisites"
check "docker CLI installed"                 command -v docker
check "Docker daemon reachable"              docker info
check "Docker Compose v2 available"          docker compose version
check "python3 installed (3.11+)"            python3 -c 'import sys; assert sys.version_info >= (3, 11)'
check "port $PORT free on this machine"      port_ok
mkdir -p "$STATE_DIR/openclaw/workspace" "$STATE_DIR/auth-profile-secrets" "$ROOT/reports"
chmod 700 "$STATE_DIR" "$STATE_DIR/openclaw" "$STATE_DIR/auth-profile-secrets" 2>/dev/null || true
check "state/ directory private (mode 700)"  test -d "$STATE_DIR/openclaw"
if ! summary; then
  echo "Fix: install Docker Desktop or Docker Engine + Compose v2 (https://docs.docker.com/get-docker/),"
  echo "start it, and free port $PORT or set OPENCLAW_GATEWAY_PORT in .env."
  exit 1
fi
