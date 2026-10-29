#!/usr/bin/env bash
# Shared helpers for L05 scripts. Sourced, not run.
# shellcheck disable=SC2034  # variables are used by the scripts that source this file

LESSON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${L05_STATE_DIR:-$LESSON_DIR/.state}"
REPORT_DIR="${L05_REPORT_DIR:-$LESSON_DIR/reports}"
OPENCLAW="${OPENCLAW_BIN:-openclaw}"
AGENT_ID="${L05_AGENT:-main}"
SKILL_NAME="uptime-report"
SKILL_SRC="$LESSON_DIR/skills/$SKILL_NAME/SKILL.md"
NEG_NAME="l05-gated-example"
PROBE_PORT="${L05_PROBE_PORT:-18999}"
PROBE_LOG="$STATE_DIR/probe.jsonl"
PROBE_PID="$STATE_DIR/probe.pid"
PROBE_MODEL="probe/skill-probe"
mkdir -p "$STATE_DIR"

PASS_N=0
FAIL_N=0
check() { # check "label" <command...> : prints one PASS/FAIL line
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '%-66s PASS\n' "$label"; PASS_N=$((PASS_N + 1))
  else
    printf '%-66s FAIL\n' "$label"; FAIL_N=$((FAIL_N + 1))
  fi
}
total() { # prints N/N PASS and returns non-zero on any failure
  local n=$((PASS_N + FAIL_N))
  if [ "$FAIL_N" -eq 0 ]; then echo "$PASS_N/$n PASS"; return 0; fi
  echo "$PASS_N/$n PASS ($FAIL_N FAIL)"; return 1
}
die() { echo "FAIL: $*" >&2; exit 1; }

need() { # need <cmd> "<fix hint>"
  command -v "$1" >/dev/null 2>&1 || die "$1 not found. Fix: $2"
}
need_python() {
  need python3 "install Python 3.11+ (python.org or your package manager)"
  python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' \
    || die "Python 3.11+ required (found $(python3 --version 2>&1))"
}
need_openclaw() {
  need "$OPENCLAW" "install OpenClaw (Lesson 01), then open a new shell"
}

# jget FILE EXPR : evaluate a Python expression against JSON loaded as d
jget() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }

sha256_of() { # portable sha256 (Linux, macOS, WSL2)
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; fi
}

workspace_dir() { # the agent's workspace, as OpenClaw reports it
  "$OPENCLAW" skills check --agent "$AGENT_ID" --json > "$STATE_DIR/check.json" 2>/dev/null || return 1
  jget "$STATE_DIR/check.json" 'd["workspaceDir"]'
}

probe_up() { python3 -c 'import sys,urllib.request; urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/health", timeout=2)' "$PROBE_PORT" 2>/dev/null; }

start_probe() { # idempotent
  if probe_up; then return 0; fi
  nohup python3 "$LESSON_DIR/src/probe_model.py" --port "$PROBE_PORT" --log "$PROBE_LOG" \
    > "$STATE_DIR/probe.out" 2>&1 &
  echo $! > "$PROBE_PID"
  for _ in 1 2 3 4 5 6 7 8 9 10; do probe_up && return 0; sleep 0.5; done
  return 1
}

stop_probe() {
  if [ -f "$PROBE_PID" ]; then kill "$(cat "$PROBE_PID")" 2>/dev/null || true; rm -f "$PROBE_PID"; fi
}

confirm() { # confirm "question" ; L05_YES=1 answers yes
  [ "${L05_YES:-0}" = "1" ] && return 0
  [ -t 0 ] || return 1
  local a; read -r -p "$1 [y/N] " a; [ "$a" = "y" ] || [ "$a" = "Y" ]
}
