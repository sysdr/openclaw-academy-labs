#!/usr/bin/env bash
# test: unit tests, mock end-to-end, shellcheck (if installed), integration (if Docker + image).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 -m unittest discover -s tests
tests/e2e_mock.sh
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x scripts/*.sh tests/*.sh solution/*.sh && echo "shellcheck clean"
else
  echo "shellcheck not installed; skipped (https://www.shellcheck.net)"
fi
tests/integration.sh
