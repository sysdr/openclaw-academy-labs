#!/usr/bin/env bash
# Assignment solution: a second skill, who-report, written to spec.
# It activates like uptime-report, but `who` is NOT on the L04 allowlist,
# so the proof is that activation does not grant permission:
#   - linter passes, OpenClaw marks it eligible and model-visible
#   - a real agent turn reads it and attempts exec
#   - exec is denied and the reply says so, in the skill's own format
# Usage: bash solution/solve.sh     (run from the lesson folder, after make setup)
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/../scripts/lib.sh"
need_python
need_openclaw

src="$STATE_DIR/who-report/SKILL.md"
mkdir -p "$(dirname "$src")"
cat > "$src" <<'EOF'
---
name: who-report
description: List who is logged in to this host right now, using the who command.
metadata: { "openclaw": { "requires": { "bins": ["who"] }, "os": ["linux", "darwin"] } }
---

# Who report

Use this skill when the user asks who is logged in to this machine.

1. Run `who` with the `exec` tool. Run nothing else.
2. Reply with exactly one line:
   `WHO-REPORT users=<comma-separated names, or none>`
3. If exec is denied or fails, reply `WHO-REPORT error=<short reason>`.
EOF

check "who-report passes the spec linter" python3 "$LESSON_DIR/src/lint_skill.py" --check-bins "$src"
ws=$(workspace_dir) || die "cannot read the agent workspace"
mkdir -p "$ws/skills/who-report"
cp "$src" "$ws/skills/who-report/SKILL.md"
ok=0
for _ in $(seq 1 30); do
  if "$OPENCLAW" skills info who-report --agent "$AGENT_ID" --json > "$STATE_DIR/who-info.json" 2>/dev/null; then ok=1; break; fi
  sleep 1
done
check "OpenClaw: who-report eligible and model-visible" test "$ok:$(jget "$STATE_DIR/who-info.json" \
  'd["eligible"] and d["modelVisible"]')" = "1:True"

# Point the probe at who-report for this run, then put it back.
stop_probe
nohup python3 "$LESSON_DIR/src/probe_model.py" --port "$PROBE_PORT" --log "$PROBE_LOG" --skill who-report \
  > "$STATE_DIR/probe.out" 2>&1 &
echo $! > "$PROBE_PID"
for _ in 1 2 3 4 5 6 7 8 9 10; do probe_up && break; sleep 0.5; done
start=$(wc -l < "$PROBE_LOG" | tr -d ' ')
"$OPENCLAW" agent --agent "$AGENT_ID" --model "$PROBE_MODEL" --session-key "l05-who-$(date +%s)" \
  --message "who is logged in right now?" --json --timeout 120 > "$STATE_DIR/who.json" || true
reply=$(jget "$STATE_DIR/who.json" 'd["result"]["meta"]["terminalReply"]["text"]' 2>/dev/null || true)
echo "   reply: $reply"
check "activated: model read who-report and attempted exec who" python3 -c '
import json,sys
recs=[json.loads(l) for i,l in enumerate(open(sys.argv[1])) if i>=int(sys.argv[2])]
sys.exit(0 if any(r.get("command")=="who" for r in recs) else 1)' "$PROBE_LOG" "$start"
check "least privilege held: exec denied, reported in the skill's format" test "$reply" = "WHO-REPORT error=exec denied"

stop_probe
start_probe >/dev/null
rm -rf "${ws:?}/skills/who-report"
total
