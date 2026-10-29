#!/usr/bin/env bash
# 60-second demo: the skill's status, one ordinary request, the model-facing trail, the reply.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need_python
need_openclaw
start_probe || die "probe did not start; see $STATE_DIR/probe.out"

echo "\$ openclaw skills info $SKILL_NAME --json   (key fields)"
"$OPENCLAW" skills info "$SKILL_NAME" --agent "$AGENT_ID" --json > "$STATE_DIR/demo-info.json"
jget "$STATE_DIR/demo-info.json" '"source=%s eligible=%s modelVisible=%s" % (d["source"], d["eligible"], d["modelVisible"])'
echo
start=$(wc -l < "$PROBE_LOG" 2>/dev/null | tr -d ' ' || echo 0)
echo "\$ openclaw agent --message 'how long has this machine been up?'"
"$OPENCLAW" agent --agent "$AGENT_ID" --model "$PROBE_MODEL" --session-key "l05-demo-$(date +%s)" \
  --message "how long has this machine been up?" --json --timeout 120 > "$STATE_DIR/demo.json"
echo
echo "what the model saw and did:"
python3 - "$PROBE_LOG" "${start:-0}" <<'PY'
import json, sys
recs = [json.loads(l) for i, l in enumerate(open(sys.argv[1])) if i >= int(sys.argv[2])]
r0 = recs[0]
print(f"  prompt lists {r0['listed_count']} skills; uptime-report listed: {r0['skill_listed']}")
for r in recs:
    detail = {"skills_read": "skills_read(name=uptime-report)", "exec": f"exec(command={r.get('command')})",
              "reply": f"reply: {r.get('reply')}"}.get(r["action"], r["action"])
    print(f"  step {r['step']}: {detail}")
PY
