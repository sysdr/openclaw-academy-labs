#!/usr/bin/env bash
# Start the probe model (if needed) and send one ordinary request through a real agent turn.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need_python
need_openclaw
start_probe || die "probe did not start; see $STATE_DIR/probe.out (is port $PROBE_PORT free?)"
msg="${1:-how long has this machine been up?}"
echo "> $msg"
"$OPENCLAW" agent --agent "$AGENT_ID" --model "$PROBE_MODEL" --session-key "l05-run-$(date +%s)" \
  --message "$msg" --json --timeout 120 > "$STATE_DIR/run.json"
jget "$STATE_DIR/run.json" 'd["result"]["meta"]["terminalReply"]["text"]'
