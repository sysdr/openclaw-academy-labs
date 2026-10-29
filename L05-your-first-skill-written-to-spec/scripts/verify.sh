#!/usr/bin/env bash
# PROOF for L05: a working skill with an activation test.
#   A. the skill is written to spec
#   B. OpenClaw discovers it, finds it ready, and makes it visible to the agent
#   C. activation: real agent turns put it in the model's prompt, hand the model
#      its instructions, run its one allowed command, and return the specified reply;
#      a gated twin never reaches the prompt (negative control)
#   D. optional: LIVE_MODEL=<provider/model> repeats C2 with your real model
# Prints N/N PASS, exits 0 only if all pass, writes reports/verify-<timestamp>.txt
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need_python
need_openclaw
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/verify-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$REPORT") 2>&1

DESC=$(python3 -c 'import sys,re; t=open(sys.argv[1]).read(); print(re.search(r"^description:\s*(.+)$", t, re.M).group(1).strip())' "$SKILL_SRC")
REPLY_RE='^UPTIME-REPORT up=[^ ].* load=[0-9.]+,[0-9.]+,[0-9.]+$'

# pq START EXPR : evaluate EXPR over the probe records written after line START
pq() {
  python3 - "$PROBE_LOG" "$1" "$2" <<'PY'
import json, sys, html
log, start, expr = sys.argv[1], int(sys.argv[2]), sys.argv[3]
recs = [json.loads(l) for i, l in enumerate(open(log, encoding="utf-8")) if i >= start and l.strip()]
sys.exit(0 if recs and eval(expr, {"recs": recs, "html": html, "re": __import__("re")}) else 1)
PY
}
log_lines() { if [ -f "$PROBE_LOG" ]; then wc -l < "$PROBE_LOG" | tr -d ' '; else echo 0; fi; }
turn() { # turn KEY MESSAGE OUT [MODEL]
  "$OPENCLAW" agent --agent "$AGENT_ID" --model "${4:-$PROBE_MODEL}" --session-key "$1" \
    --message "$2" --json --timeout 120 > "$3" 2>"$3.err"
}
matches() { printf '%s\n' "$1" | grep -Eq "$2"; }
reply_of() { jget "$1" 'd["result"]["meta"]["terminalReply"]["text"]' 2>/dev/null || true; }

echo "== A. written to spec"
check "SKILL.md passes the spec linter (R1-R8)" python3 "$LESSON_DIR/src/lint_skill.py" --check-bins "$SKILL_SRC"
ws=$(workspace_dir) || ws=""
check "agent workspace found ($AGENT_ID)" test -n "$ws"
check "installed copy matches the repo (sha256)" \
  test "$(sha256_of "$ws/skills/$SKILL_NAME/SKILL.md" 2>/dev/null)" = "$(sha256_of "$SKILL_SRC")"

echo "== B. discovered, ready, visible"
"$OPENCLAW" skills info "$SKILL_NAME" --agent "$AGENT_ID" --json > "$STATE_DIR/info.json" 2>/dev/null || echo '{}' > "$STATE_DIR/info.json"
check "gateway health is ok" "$OPENCLAW" health --json
check "inventory: source is openclaw-workspace" test "$(jget "$STATE_DIR/info.json" 'd.get("source")')" = openclaw-workspace
check "readiness: eligible, nothing missing" test "$(jget "$STATE_DIR/info.json" \
  'd.get("eligible") is True and not any(d.get("missing",{}).values())')" = True
check "visibility: modelVisible for agent $AGENT_ID" test "$(jget "$STATE_DIR/info.json" 'd.get("modelVisible")')" = True
check "skills check lists it as model-visible" test "$(jget "$STATE_DIR/check.json" \
  "'$SKILL_NAME' in [s if isinstance(s,str) else s.get('name') for s in d.get('modelVisible',[])]")" = True

echo "== C. activation test (real agent turns, scripted probe model)"
check "probe model up on 127.0.0.1:$PROBE_PORT" start_probe
# Negative control: same shape, but it needs a binary that does not exist.
neg="$ws/skills/$NEG_NAME"
cleanup() { [ -n "$ws" ] && rm -rf "${neg:?}"; }
trap cleanup EXIT
mkdir -p "$neg"
cat > "$neg/SKILL.md" <<'EOF'
---
name: l05-gated-example
description: Negative control for the L05 activation test; needs a binary that does not exist.
metadata: { "openclaw": { "requires": { "bins": ["l05-no-such-binary"] } } }
---

This skill must never reach the model.
EOF
seen=0
for _ in $(seq 1 30); do
  if "$OPENCLAW" skills info "$NEG_NAME" --agent "$AGENT_ID" --json > "$STATE_DIR/neg.json" 2>/dev/null; then seen=1; break; fi
  sleep 1
done
check "negative control discovered but not eligible (missing bin)" test "$seen:$(jget "$STATE_DIR/neg.json" \
  'd.get("eligible") is False and "l05-no-such-binary" in d.get("missing",{}).get("bins",[])' 2>/dev/null)" = "1:True"

start=$(log_lines)
turn "l05-verify-$(date +%s)-a" "how long has this machine been up?" "$STATE_DIR/turn1.json" || true
check "C1 prompt lists $SKILL_NAME with its exact description" pq "$start" \
  "f'<name>$SKILL_NAME</name>' in recs[0]['system_prompt'] and html.escape('''$DESC''') in recs[0]['system_prompt']"
check "C1 prompt omits the gated negative control" pq "$start" \
  "all('<name>$NEG_NAME</name>' not in r['system_prompt'] for r in recs)"
check "C2 skills_read returned the skill body to the model" pq "$start" \
  "any(r.get('skill_body_received') for r in recs)"
check "C3 exec ran uptime and was allowed (L04 allowlist)" pq "$start" \
  "any(r.get('action')=='reply' and 'denied' not in r.get('reply','') and 'error' not in r.get('reply','') for r in recs)"
r1=$(reply_of "$STATE_DIR/turn1.json")
echo "   reply: $r1"
check "C4 reply matches the skill's output spec" matches "$r1" "$REPLY_RE"

start=$(log_lines)
turn "l05-verify-$(date +%s)-b" "\$$SKILL_NAME" "$STATE_DIR/turn2.json" || true
check "C5 explicit \$$SKILL_NAME: OpenClaw tells the model to read it" pq "$start" \
  "re.search(r'referenced skills.*\n- $SKILL_NAME\b', recs[0]['user_text'], re.S) is not None"

if [ -n "${LIVE_MODEL:-}" ]; then
  echo "== D. live model: $LIVE_MODEL"
  turn "l05-verify-$(date +%s)-live" "how long has this machine been up?" "$STATE_DIR/live.json" "$LIVE_MODEL" || true
  rl=$(reply_of "$STATE_DIR/live.json")
  echo "   reply: $rl"
  check "D1 your model chose the skill and replied to spec" matches "$rl" "$REPLY_RE"
else
  echo "(D skipped: set LIVE_MODEL=<provider/model> to test with your real model)"
fi
total
