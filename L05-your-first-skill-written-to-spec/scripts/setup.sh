#!/usr/bin/env bash
# Install the skill into the agent's workspace and register the local probe model.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
need_python
need_openclaw

python3 "$LESSON_DIR/src/lint_skill.py" --check-bins "$SKILL_SRC" >/dev/null \
  || die "SKILL.md fails the spec linter. Run: make build"

ws=$(workspace_dir) || die "cannot read the agent workspace. Is the gateway running? Try: openclaw health"
dest="$ws/skills/$SKILL_NAME"
mkdir -p "$dest"
if [ -f "$dest/SKILL.md" ] && [ "$(sha256_of "$dest/SKILL.md")" != "$(sha256_of "$SKILL_SRC")" ]; then
  cp "$dest/SKILL.md" "$STATE_DIR/SKILL.md.previous"
  confirm "A different $SKILL_NAME exists in $dest (saved to .state). Replace it?" \
    || die "kept the existing skill; rerun with L05_YES=1 to replace"
fi
cp "$SKILL_SRC" "$dest/SKILL.md"
check "skill copied to <workspace>/skills/$SKILL_NAME" test -f "$dest/SKILL.md"

"$OPENCLAW" config patch --file "$LESSON_DIR/config/probe-provider.patch.json" >/dev/null
check "probe model registered as $PROBE_MODEL (127.0.0.1 only)" \
  test "$("$OPENCLAW" config get models.providers.probe.baseUrl)" = "http://127.0.0.1:$PROBE_PORT/v1"
check "probe model listening on 127.0.0.1:$PROBE_PORT" start_probe
total
