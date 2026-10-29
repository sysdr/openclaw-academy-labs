#!/usr/bin/env bash
# Validate everything before OpenClaw sees it: the skill against the spec,
# the JSON config, the Python, and (if OpenClaw is installed) a dry-run patch.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need_python

python3 "$LESSON_DIR/src/lint_skill.py" --check-bins "$SKILL_SRC" || true
check "SKILL.md passes the spec linter (R1-R8)" python3 "$LESSON_DIR/src/lint_skill.py" --check-bins "$SKILL_SRC"
for f in "$LESSON_DIR"/config/*.json "$LESSON_DIR"/fixtures/*.json; do
  check "valid JSON: ${f#"$LESSON_DIR"/}" python3 -m json.tool "$f"
done
check "python sources compile" python3 -m py_compile "$LESSON_DIR"/src/*.py "$LESSON_DIR"/tests/*.py
if command -v "$OPENCLAW" >/dev/null 2>&1; then
  check "openclaw accepts the probe provider patch (dry run)" \
    "$OPENCLAW" config patch --file "$LESSON_DIR/config/probe-provider.patch.json" --dry-run
else
  echo "openclaw not installed: skipping dry-run patch"
fi
total
