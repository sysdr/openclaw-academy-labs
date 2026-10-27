#!/usr/bin/env bash
# Applies this lesson's two changes: requested exec policy (openclaw.json) and host approvals.
# `approvals set` REPLACES the whole approvals document, so the current one is backed up first.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
prereqs
backup="$STATE/approvals-backup-$(date +%Y%m%d-%H%M%S).json"
"$OC" approvals get --json 2>/dev/null | "$PY" -c 'import json,sys; json.dump(json.load(sys.stdin).get("file",{}),sys.stdout,indent=2)' >"$backup"
pass "backed up current approvals to ${backup#"$ROOT"/}"
if [ "${YES:-}" != "1" ] && [ -t 0 ]; then
  read -r -p "Replace exec approvals with config/exec-approvals.json? [y/N] " answer
  case "$answer" in y|Y) ;; *) echo "aborted, nothing changed"; exit 1;; esac
fi
"$OC" config patch --file "$ROOT/config/openclaw.exec.patch.json" >/dev/null && pass "tools.exec + probe provider patched into openclaw.json"
# Newer OpenClaw gates --model overrides behind modelPolicy.allow; keep existing entries and add the probe.
if "$PY" - "$OC" <<'PY'
import json, subprocess, sys
oc = sys.argv[1]

def load_json(argv):
    proc = subprocess.run(argv, capture_output=True, text=True)
    text = (proc.stdout or "").strip()
    # Prefer the last JSON object if the CLI prefixes log lines.
    for chunk in reversed(text.splitlines() or [text]):
        chunk = chunk.strip()
        if chunk.startswith("{"):
            return json.loads(chunk)
    return {}

try:
    policy = load_json([oc, "config", "get", "agents.defaults.modelPolicy", "--json"])
except (json.JSONDecodeError, FileNotFoundError, subprocess.SubprocessError):
    policy = {}
allow = list(policy.get("allow") or [])
# Empty allow means "any model". Do not replace that with a probe-only list.
if not allow:
    sys.exit(0)
needed = ["probe/exec-probe", "probe/*"]
merged = allow + [x for x in needed if x not in allow]
if merged != allow:
    patch = {"agents": {"defaults": {"modelPolicy": {"allow": merged}}}}
    proc = subprocess.run(
        [oc, "config", "patch", "--stdin"],
        input=json.dumps(patch),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr or proc.stdout or "config patch failed\n")
        sys.exit(1)
sys.exit(0)
PY
then pass "probe model allowed in agents.defaults.modelPolicy.allow"
else fail "probe model allowed in agents.defaults.modelPolicy.allow" "add probe/* to agents.defaults.modelPolicy.allow"
fi
"$OC" approvals set --file "$ROOT/config/exec-approvals.json" >/dev/null && pass "exec approvals replaced from config/exec-approvals.json"
echo "$PASSES/$TOTAL PASS"
