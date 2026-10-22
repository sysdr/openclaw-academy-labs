#!/usr/bin/env bash
# End-to-end test: runs the REAL scripts/verify.sh against tests/mock/docker,
# once in a passing state and once in a failing state, and compares the
# PASS/FAIL column with expected/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASSES=0; FAILS=0
ok()  { printf '%-52s PASS\n' "$1"; PASSES=$((PASSES + 1)); }
bad() { printf '%-52s FAIL\n' "$1"; FAILS=$((FAILS + 1)); }

# Build a throwaway copy of the lesson with state files in the given modes.
make_copy() {
  local dir="$1" envmode="$2" statemode="$3" cfgmode="$4" ignore="$5"
  mkdir -p "$dir"
  cp -R "$ROOT/scripts" "$ROOT/src" "$ROOT/docker" "$dir/"
  printf 'OPENCLAW_VERSION=2026.10.5\nOPENCLAW_GATEWAY_TOKEN=test-not-a-secret\n' > "$dir/.env"
  if [ "$ignore" = yes ]; then printf '.env\nstate/\n' > "$dir/.gitignore"; else printf 'state/\n' > "$dir/.gitignore"; fi
  mkdir -p "$dir/state/openclaw"
  echo '{}' > "$dir/state/openclaw/openclaw.json"
  chmod "$envmode" "$dir/.env"; chmod "$statemode" "$dir/state/openclaw"; chmod "$cfgmode" "$dir/state/openclaw/openclaw.json"
}

# Keep only "NN. description STATUS" so timestamps and details don't matter.
columns() { grep -E '^ ?[0-9]+\. ' "$1" | sed -E 's/  (PASS|FAIL)  .*/  \1/'; grep -E '^[0-9]+/[0-9]+ PASS$' "$1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export PATH="$ROOT/tests/mock:$PATH"

t() { local label="$1"; shift; if "$@" > "$TMP/last" 2>&1; then ok "$label"; else bad "$label"; cat "$TMP/last"; fi; }
not() { ! "$@"; }
matches() { columns "$1" | diff -u "$2" -; }

make_copy "$TMP/good" 600 700 600 yes
t "passing state: verify.sh exits 0" env MOCK_CASE=good "$TMP/good/scripts/verify.sh"
MOCK_CASE=good "$TMP/good/scripts/verify.sh" > "$TMP/good.out" 2>&1 || true
t "passing state: prints 10/10 PASS" grep -qx '10/10 PASS' "$TMP/good.out"
t "passing state matches expected/verify-pass.txt" matches "$TMP/good.out" "$ROOT/expected/verify-pass.txt"

make_copy "$TMP/bad" 644 755 644 no
t "failing state: verify.sh exits 1" not env MOCK_CASE=bad "$TMP/bad/scripts/verify.sh"
MOCK_CASE=bad "$TMP/bad/scripts/verify.sh" > "$TMP/bad.out" 2>&1 || true
t "failing state: prints 0/10 PASS" grep -qx '0/10 PASS' "$TMP/bad.out"
t "failing state matches expected/verify-fail.txt" matches "$TMP/bad.out" "$ROOT/expected/verify-fail.txt"
t "verify.sh wrote a timestamped report" compgen -G "$TMP/good/reports/verify-*.txt"

echo "e2e mock: $PASSES/$((PASSES + FAILS)) PASS"
[ "$FAILS" -eq 0 ]
