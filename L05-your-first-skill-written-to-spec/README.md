# L05 - Your first skill, written to spec

**Goal:** write one OpenClaw skill (`uptime-report`) that follows the SKILL.md spec exactly, and prove it activates.

**Proof:** `make verify` prints `16/16 PASS`: the skill passes an 8-rule spec linter, OpenClaw reports it eligible and model-visible, and real agent turns show it in the model's prompt, hand the model its instructions, run its one allowlisted command, and return the specified reply. A gated twin never reaches the prompt.

Verified on OpenClaw 2026.10.7 (157d8c2), Node 24.22.1, Python 3.13, Ubuntu (sandbox). macOS and WSL2: see VERIFICATION.md.

Article: https://openclawacademy.substack.com (Lesson 05)
Code: https://github.com/sysdr/openclaw-academy-labs-p/tree/main/L05-your-first-skill-written-to-spec

## Quickstart

```bash
make bootstrap   # only if you skipped L03/L04
make build
make setup
make verify
make demo
```

## Files

- `skills/uptime-report/SKILL.md` - the skill, written to spec
- `src/lint_skill.py` - spec linter (rules R1-R8; stricter than the loader on purpose)
- `src/probe_model.py` - scripted local model on 127.0.0.1:18999 that records prompts and follows one skill
- `config/probe-provider.patch.json` - registers the probe as `probe/skill-probe`
- `config/l04-exec-approvals.json` - L04 allowlist, used only by `make bootstrap`
- `config/README.md` - every config key explained
- `scripts/lib.sh` - shared helpers (PASS/FAIL lines, probe start/stop, portable sha256)
- `scripts/bootstrap.sh` - recreates the L03/L04 end state
- `scripts/build.sh` - lint, JSON, Python, dry-run patch
- `scripts/setup.sh` - installs the skill into your workspace, registers the probe
- `scripts/run.sh` - one ordinary request through a real agent turn
- `scripts/test.sh` - unit tests and the mock end-to-end test
- `scripts/verify.sh` - the proof; writes `reports/verify-<timestamp>.txt`
- `scripts/demo.sh` - 60-second walkthrough
- `scripts/clean.sh` - stops the probe, removes local state, asks before touching your workspace
- `tests/test_lint.py` - linter cases from fixtures, plus an integration test (skips without OpenClaw)
- `tests/test_probe.py` - probe decisions and uptime parsing (Linux and macOS formats)
- `tests/mock_openclaw.py` - stand-in CLI for offline tests
- `tests/e2e_verify_mock.sh` - runs the real verify.sh against the mock, passing and failing
- `fixtures/lint-cases.json` - nine SKILL.md cases, three of which OpenClaw itself loads or skips silently
- `expected/verify-pass.txt` - what a passing run looks like
- `solution/solve.sh` - assignment: a second skill that activates but is denied by the L04 allowlist

## Safety

- Gateway stays on loopback with token auth (L03). The probe binds 127.0.0.1 only.
- Exec approvals stay on (L04). The skill needs exactly one allowlisted binary, `/usr/bin/uptime`.
- No secrets anywhere. The probe needs no key. Token scope: the gateway token from L03 is read from
  `OPENCLAW_GATEWAY_TOKEN` and is used only by the local CLI; no other credentials are involved.
- `make bootstrap` replaces exec approvals only after a backup and a yes.
- `verify.sh` adds a negative-control skill to your workspace and removes it on exit.
