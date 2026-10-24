# L03 - Gateway authentication and loopback binding

**Goal:** put two independent locks on the OpenClaw Gateway: it listens only on `127.0.0.1`, and every caller must present a 256-bit token.

**Proof:** `make verify` prints `10/10 PASS`: the Gateway answers on `127.0.0.1`, refuses connections on every LAN address of the machine, returns `401` without the token, and accepts the token from `.env`.

Verified on OpenClaw **v2026.10.6** (the 2.x line; v2026.8.1 is "OpenClaw 2.0"). Article: https://openclawacademy.substack.com
Code: https://github.com/sysdr/openclaw-academy-labs-p/tree/main/L03-gateway-authentication-and-loopback-binding

## Quickstart

```bash
make bootstrap   # confirms the L01 install and L02 audit are in place
make setup       # token into .env (600), bind=loopback, auth.mode=token
make run         # Gateway in the foreground (MOCK=1 make run to practice without OpenClaw)
make verify      # in a second terminal: expect 10/10 PASS
make demo        # 60-second show-and-tell
```

## Token scope (least privilege)

The Gateway token is a **full operator credential**. OpenClaw's docs state that shared-secret
bearer auth grants the full default operator scope set (`operator.admin`, `operator.approvals`,
`operator.pairing`, `operator.read`, `operator.talk.secrets`, `operator.write`) and that narrower
`x-openclaw-scopes` headers do not reduce it. So: one token per Gateway, never shared with another
person or service, kept off the network by the loopback bind. Narrower identities need
`trusted-proxy` auth with roles (Season 3).

## Files

- `Makefile` - targets bootstrap, setup, build, run, test, verify, demo, clean; each calls one script.
- `config/openclaw.gateway.json5` - the only config keys this lesson adds (no token inside).
- `config/README.md` - what each key does, plus the Docker path.
- `docker/compose.loopback.yml` - Compose override that publishes the port on 127.0.0.1 only.
- `scripts/lib.sh` - shared helpers: PASS/FAIL lines, token loading, port resolution.
- `scripts/bootstrap.sh` - checks the end state of L01 (install) and L02 (audit).
- `scripts/setup.sh` - generates the token into `.env` and applies `openclaw config set`.
- `scripts/build.sh` - validates the config fragment and Python sources.
- `scripts/run.sh` - starts the Gateway with `--bind loopback --auth token` (or the mock).
- `scripts/test.sh` - unit tests, mock end-to-end test, live test, shellcheck.
- `scripts/verify.sh` - the proof: 10 checks, `N/N PASS`, report in `reports/`.
- `scripts/demo.sh` - health, LAN refusal, 401, 200, verify summary.
- `scripts/clean.sh` - removes reports and caches; asks before deleting `.env`.
- `src/gwcheck.py` - JSON5 reader, listener lookup (ss, lsof, netstat, /proc), local IPs.
- `tests/mock_gateway.py` - stand-in for `/health` and `/tools/invoke`.
- `tests/test_gwcheck.py` - unit tests, no OpenClaw needed.
- `tests/test_e2e_verify.py` - runs the real `verify.sh` against the mock, passing and failing.
- `tests/test_integration_live.py` - live checks, skipped when OpenClaw is absent.
- `fixtures/good.json5`, `fixtures/bad.json5` - configs for the passing and failing states.
- `expected/verify-pass.txt` - what a passing run looks like.
- `solution/rotate-token.sh`, `solution/README.md` - assignment solution (token rotation drill).
- `.env.example` - placeholder only. `VERIFICATION.md` - every command and key with its source.

## Safety

- The Gateway stays on loopback. Remote access belongs to an SSH tunnel or Tailscale Serve, not `bind: "lan"`.
- The token never appears in `openclaw.json`, in script output, or in `ps` (curl reads the header from stdin).
- Nothing here needs `sudo`. `clean.sh` asks before deleting your token.

MIT licensed.
