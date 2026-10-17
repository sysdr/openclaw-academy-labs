## Implementation Guide : Lesson 01 - Install OpenClaw 2.0 inside a sandbox (Docker or VM)

This guide covers every way to run this lesson from **inside this project directory only**. Work from:

```bash
cd L01-install-openclaw-2-0-inside-a-sandbox
```

### What this project does

Runs the OpenClaw Gateway (`2026.10.4`) inside a hardened Docker sandbox: loopback-only port, capabilities dropped, no Docker socket, exec policy deny. Proof is an agent reply that echoes a fresh one-time token.

### Prerequisites

- Docker Engine (or Docker Desktop) with Compose v2
- Python 3.11+
- A free host port (default `18789`)
- A model API key in `.env` (Google AI Studio / Gemini by default; OpenAI also supported)

### Prepare environment (once)

```bash
cp .env.example .env
chmod 600 .env
```

Edit `.env` and set:

| Variable | Purpose |
|----------|---------|
| `GEMINI_API_KEY` | Google AI Studio key (https://aistudio.google.com/apikey) |
| `OPENCLAW_AUTH_CHOICE` | Default `gemini-api-key` (or `openai-api-key` + `OPENAI_API_KEY`) |
| `OPENCLAW_GATEWAY_PORT` | Host port, default `18789` |
| `OPENCLAW_IMAGE` | Pinned image `ghcr.io/openclaw/openclaw:2026.10.4` |

Generate a gateway token if empty (32-byte hex), then first-time onboard and apply exec deny:

```bash
# token (if OPENCLAW_GATEWAY_TOKEN is still empty in .env)
python3 -c 'import secrets; print(secrets.token_hex(32))'
# paste into .env as OPENCLAW_GATEWAY_TOKEN=...

mkdir -p state/openclaw/workspace state/auth-profile-secrets
chmod 700 state state/openclaw state/auth-profile-secrets

# first-time headless onboard (Gemini example; image must be available — run make build first if needed)
docker compose --project-directory "$PWD" -f docker/compose.yaml --env-file .env \
  run -T --rm --no-deps --entrypoint node openclaw-gateway dist/index.js onboard \
  --non-interactive --accept-risk --skip-health --mode local \
  --auth-choice gemini-api-key --secret-input-mode ref \
  --gateway-auth token --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
  --gateway-bind lan --skip-channels --no-install-daemon

docker compose --project-directory "$PWD" -f docker/compose.yaml --env-file .env \
  run -T --rm --no-deps --entrypoint node openclaw-gateway dist/index.js \
  approvals set --stdin < config/exec-approvals.json5

# pin a Flash model that works for new Google AI Studio keys
docker compose --project-directory "$PWD" -f docker/compose.yaml --env-file .env \
  run -T --rm --no-deps --entrypoint node openclaw-gateway dist/index.js \
  models set google/gemini-3.8-flash
```

On Linux, the container user is uid `1000`. If `state/` is not owned by uid 1000:

```bash
sudo chown -R 1000:1000 state
```

---

### Way 1 — Makefile (recommended)

```bash
make bootstrap   # Docker, Compose, python3, port free
make build       # pull pinned image, validate compose
make run         # start Gateway; wait until /startupz is 200 + healthy
make verify      # 11 sandbox + agent checks
make demo        # optional 60-second walkthrough
make stop        # stop lesson containers
```

Handy extras:

```bash
make test        # unit + mock e2e (no live API needed for those)
make clean       # stop containers; asks before deleting state/ and .env
make help        # list targets
```

---

### Way 2 — Scripts directly

Same lifecycle as the Makefile, calling scripts under `scripts/`:

```bash
bash scripts/bootstrap.sh
bash scripts/build.sh
bash scripts/run.sh
bash scripts/verify.sh
bash scripts/demo.sh
bash scripts/stop.sh
bash scripts/test.sh
```

Full teardown of containers, unused Docker objects, local `.env` / `state` / `reports`:

```bash
bash cleanup.sh
```

---

### Way 3 — Manual Docker Compose

After `.env` exists and onboarding has written `state/openclaw/openclaw.json`:

```bash
docker compose --project-directory "$PWD" \
  -f docker/compose.yaml --env-file .env \
  up -d openclaw-gateway

# Wait until ready
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18789/startupz
# expect: 200

docker compose --project-directory "$PWD" \
  -f docker/compose.yaml --env-file .env ps

docker compose --project-directory "$PWD" \
  -f docker/compose.yaml --env-file .env \
  exec -T openclaw-gateway node dist/index.js \
  agent --agent main --timeout 120 --json \
  --message "Reply with exactly this token and nothing else: SANDBOX-OK-demo1"
```

Stop manually:

```bash
docker compose --project-directory "$PWD" \
  -f docker/compose.yaml --env-file .env \
  down --remove-orphans
```

---

### Way 4 — Offline / no API key (integration path)

Uses the real image plus `tests/fake_llm.py` (no cloud key):

```bash
make build
bash tests/integration.sh
```

Expect `INTEGRATION PASS` and `11/11 PASS` in the output. Skips cleanly if Docker or the image is missing.

---

### How to see the output

**Verify proof (primary)**

```bash
make verify
```

Look for:

```text
11/11 PASS
   agent said: SANDBOX-OK-<hex>
Report: reports/verify-<timestamp>.txt
```

Open the report file under `reports/` for a saved copy of the same lines.

**Live Gateway health**

```bash
curl -s http://127.0.0.1:18789/startupz
# {"ok":true,"status":"started"}

curl -s http://127.0.0.1:18789/healthz
# {"ok":true,"status":"live"}
```

**Container status and hardening**

```bash
docker compose --project-directory "$PWD" -f docker/compose.yaml --env-file .env ps
docker port "$(docker compose --project-directory "$PWD" -f docker/compose.yaml --env-file .env ps -q openclaw-gateway)" 18789/tcp
# expect: 127.0.0.1:18789

make demo
```

**Logs**

```bash
docker compose --project-directory "$PWD" -f docker/compose.yaml --env-file .env \
  logs --tail 80 openclaw-gateway
```

**Unit / mock tests (no Gateway required)**

```bash
make test
# or: python3 -m unittest discover -s tests -p 'test_*.py'
#      bash tests/e2e_mock.sh
```

---

### Success metrics

- `make bootstrap` prints `6/6 PASS`
- `make build` prints a digest for `ghcr.io/openclaw/openclaw:2026.10.4` and `OpenClaw 2026.10.4`
- Gateway is `healthy` and `/startupz` returns HTTP `200`
- Host publish is **only** `127.0.0.1:<port>` (not `0.0.0.0`)
- Process inside the container is **not** uid `0`
- `no-new-privileges` is set; capabilities dropped; Docker socket **not** mounted
- Exec policy effective security is **deny**
- `make verify` ends with **`11/11 PASS`** and an `agent said: SANDBOX-OK-...` line
- `make test` unit suite is green; mock e2e reports `e2e mock: 4/4 PASS`
- After `bash cleanup.sh`, no `openclaw-l01*` containers remain and `.env` / `state/` / `reports/` are gone

---

### Troubleshooting (short)

| Symptom | Likely fix |
|---------|------------|
| Check 11 FAIL, `429` / quota | Wait for quota reset, or use a paid/higher-limit Google key; lesson pins `google/gemini-3.8-flash` |
| Check 11 FAIL, model `404` | Set model to `google/gemini-3.8-flash` (or `google/gemini-flash-latest`) inside the running Gateway |
| `state/` permission errors on Linux | `sudo chown -R 1000:1000 state` |
| Port in use | Change `OPENCLAW_GATEWAY_PORT` in `.env` |
| Want a clean slate | `bash cleanup.sh`, then recreate `.env` from `.env.example` and start again from Way 1 |

---

### Project layout (quick map)

| Path | Role |
|------|------|
| `Makefile` | One target per lifecycle step |
| `docker/compose.yaml` | Hardened Gateway sandbox |
| `config/exec-approvals.json5` | Exec deny policy |
| `scripts/` | bootstrap, build, run, verify, demo, stop, clean, test |
| `cleanup.sh` | Stop containers + prune unused Docker + wipe local secrets/runtime |
| `.env.example` | Template (commit); real `.env` stays local |
| `tests/` | Unit, mock e2e, optional integration with fake LLM |
| `solution/` | Optional read-only rootfs assignment |
