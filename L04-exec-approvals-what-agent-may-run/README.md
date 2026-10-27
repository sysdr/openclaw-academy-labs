# L04 - Exec approvals: scope exactly what your agent may run

**Goal:** replace OpenClaw's default exec policy (`security=full`, `ask=off`) with a three-entry allowlist that fails closed, and prove it by sending denied commands through the real exec tool.

**Proof:** `make verify` prints `21/21 PASS`: the live approvals match `config/exec-approvals.json`, `uptime`, `/bin/ls /` and `git status` run, and `curl`, `git push`, a chained `touch` and a redirection are refused by OpenClaw, with no side effect left on disk.

Verified on OpenClaw 2026.10.7 (157d8c2), Node 24.22.1, Python 3.13, Linux. Article: https://openclawacademy.substack.com (Lesson 04).
Code: https://github.com/sysdr/openclaw-academy-labs-p/tree/main/L04-exec-approvals-what-agent-may-run

## Quickstart (inside your L01 sandbox, gateway from L03 running)

```bash
make bootstrap   # recreates L03's end state if you skipped it
make build       # validates every config file
make setup       # backs up current approvals, then applies this lesson's two configs
make verify      # 21/21 PASS, report in reports/
make demo        # one allowed, one denied, 60 seconds
```

## Safety

- Gateway stays on loopback with token auth (L03). The token lives in your shell, never in a file.
- The probe model binds to `127.0.0.1:18999`, has no auth and no key, and only runs when you pass `--model probe/exec-probe`.
- `make setup` replaces the whole approvals document, so it backs up the current one to `.state/` and asks first (`YES=1` skips the prompt).
- Token scope: this lab needs only the gateway token from L03. No model API keys, no channel tokens.
- `make clean RESTORE=1` puts your previous approvals back.

## Files

- `Makefile` one target per script in `scripts/`.
- `config/exec-approvals.json` host approvals: deny by default, three-entry allowlist for `main`, fail closed.
- `config/openclaw.exec.patch.json` requested `tools.exec` policy plus the loopback probe provider.
- `config/README.md` every key explained.
- `src/probe_model.py` scripted OpenAI-compatible model: turns `RUN: <cmd>` into one exec tool call and logs OpenClaw's answer.
- `src/l04.py` policy checks, case expansion, result classification (stdlib only).
- `scripts/common.sh` shared helpers: PASS/FAIL lines, prerequisites, probe lifecycle.
- `scripts/bootstrap.sh` recreates L03's end state (loopback, token auth).
- `scripts/setup.sh` backs up and applies both configs.
- `scripts/build.sh` validates JSON and dry-runs the config patch.
- `scripts/run.sh` starts the probe model.
- `scripts/test.sh` unit tests plus the mock end-to-end test.
- `scripts/verify.sh` checks PROOF, prints N/N PASS, writes `reports/verify-<timestamp>.txt`.
- `scripts/demo.sh` one allowed and one denied command.
- `scripts/clean.sh` stops the probe, removes run state, optional restore.
- `tests/test_l04.py` unit tests (no OpenClaw) and a live test (`L04_LIVE=1`).
- `tests/mock_openclaw` stand-in CLI with a correct and a loose state.
- `tests/e2e_mock.sh` runs the real `verify.sh` against the mock in both states.
- `fixtures/cases.json` the seven command cases verify.sh sends.
- `fixtures/approvals-loose.json` a deliberately unsafe policy for negative tests.
- `expected/verify-pass.txt` real output from a passing run.
- `solution/` assignment answer: `df -h` entry and five extra cases.
- `VERIFICATION.md` every command and key with its source, quality gates, self-check.
