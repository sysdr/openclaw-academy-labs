#!/usr/bin/env bash
# test: unit tests and the mock end-to-end test run anywhere (no Docker, no
# OpenClaw, no API key). The integration test runs only when Docker and the
# pinned image are present, and skips cleanly otherwise.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "== unit tests"
python3 -m unittest discover -s tests -p 'test_*.py'
echo "== mock end-to-end (real verify.sh, mock docker)"
bash tests/e2e_mock.sh
if command -v shellcheck >/dev/null 2>&1; then
  echo "== shellcheck"
  shellcheck -x scripts/*.sh tests/*.sh tests/mock/docker tests/mock/curl && echo "shellcheck clean"
fi
if [ "${SKIP_INTEGRATION:-0}" != 1 ]; then
  echo "== integration (real OpenClaw image, offline fake model)"
  bash tests/integration.sh
fi
