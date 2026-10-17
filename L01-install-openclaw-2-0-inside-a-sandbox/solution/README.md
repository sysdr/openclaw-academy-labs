# Assignment solution: a read-only sandbox

Goal: the Gateway container's root filesystem is read-only, every write it needs goes to an explicit tmpfs or volume, and `verify.sh` gains a 12th check. Done when `make verify` prints `12/12 PASS`.

## 1. Overlay

`compose.readonly.yaml` sets `read_only: true` and adds exactly three writable places:

- `/tmp` as tmpfs (mode 1777, noexec). OpenClaw prefers `/tmp/openclaw` as its temp root.
- `/home/node/.cache` as tmpfs owned by uid 1000. In testing, OpenClaw 2026.10.4 fell back to `/home/node/.cache/openclaw-1000` under a read-only root and refused to start until this existed (`Unable to create fallback OpenClaw temp dir ... ENOENT`).
- `state/update-captures` bound to `/home/node/.openclaw.update-captures`, where the official image entrypoint keeps a pre-repair copy of state on upgrades. [VERIFY: confirm on the official image that no other path outside these three is written on first start and after an image upgrade.]

Create the capture dir first (Linux: owned by uid 1000), then start:

```bash
mkdir -p state/update-captures
docker compose --project-directory . -f docker/compose.yaml \
  -f solution/compose.readonly.yaml --env-file .env up -d openclaw-gateway
```

## 2. The 12th check

`src/l01_checks.py inspect` already reports `read_only_rootfs`. In `scripts/verify.sh`, add this line right before `summary` in `run_checks`:

```bash
  check "12. Root filesystem is read-only"   fact read_only_rootfs
```

Add the same line to `expected/verify.txt` (PASS in the `## pass` section, FAIL in `## fail`), update both totals (`12/12 PASS` and `4/12 PASS (8 FAIL)`), and add `"ReadonlyRootfs": true` to `inspect_safe` in `fixtures/cases.json` and flip `read_only_rootfs` to `True` in `tests/test_checks.py`, so `make test` stays green.

## 3. How to find the writes yourself

Start with `read_only: true` and only `/tmp`, then read the reason line:

```bash
docker compose --project-directory . -f docker/compose.yaml -f solution/compose.readonly.yaml \
  --env-file .env run --rm -T -e OPENCLAW_DEBUG=1 --no-deps openclaw-gateway \
  node dist/index.js gateway --bind lan --port 18789 2>&1 | grep Reason
```

Each `EROFS` or `ENOENT` names one path. Add the narrowest mount for it, rerun, repeat.
