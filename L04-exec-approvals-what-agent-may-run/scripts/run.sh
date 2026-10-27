#!/usr/bin/env bash
# Starts the scripted probe model on 127.0.0.1 so commands reach the real exec tool.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
probe_start
pass "probe model listening on 127.0.0.1:$PROBE_PORT (pid $(cat "$PROBE_PID" 2>/dev/null || echo mock))"
echo "try: openclaw agent --agent main --model probe/exec-probe --message 'RUN: uptime' --json"
