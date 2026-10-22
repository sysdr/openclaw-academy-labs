#!/usr/bin/env bash
# Assignment solution: turn the audit into a drift alarm.
#   solution/drift.sh --save   record today's state as the baseline
#   solution/drift.sh          exit 1 and name anything NEW since the baseline:
#                              a check that went PASS -> FAIL, or an OpenClaw
#                              finding (checkId) that was not there before.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE="$ROOT/reports/baseline.json"
EV="$(mktemp -d)"; trap 'rm -rf "$EV"' EXIT
mkdir -p "$ROOT/reports"

AUDIT_EVIDENCE_DIR="$EV" "$ROOT/scripts/audit.sh" > "$EV/audit.txt" 2>&1 || true

python3 - "$EV" "$BASELINE" "${1:-}" <<'PY'
import json, re, sys
from pathlib import Path
ev, baseline, mode = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
checks = {}
for line in (ev / "audit.txt").read_text().splitlines():
    m = re.match(r"\s*(\d+)\.\s+(.*?)\s+(PASS|FAIL)\b", line)
    if m:
        checks[m.group(2)] = m.group(3)
findings = []
audit = ev / "oc-audit.json"
if audit.exists():
    text = audit.read_text()
    findings = sorted({f["checkId"] for f in json.loads(text[text.find("{"):]).get("findings", [])})
now = {"checks": checks, "findings": findings}
if mode == "--save":
    baseline.write_text(json.dumps(now, indent=1))
    print(f"baseline saved: {sum(v == 'PASS' for v in checks.values())}/{len(checks)} PASS, {len(findings)} findings")
    sys.exit(0)
if not baseline.exists():
    print("no baseline yet: run solution/drift.sh --save first")
    sys.exit(2)
old = json.loads(baseline.read_text())
drift = [f"check now FAIL: {k}" for k, v in checks.items() if v == "FAIL" and old["checks"].get(k) != "FAIL"]
drift += [f"new finding: {f}" for f in findings if f not in old["findings"]]
if drift:
    print("DRIFT DETECTED")
    print("\n".join(drift))
    sys.exit(1)
print("no drift")
PY
