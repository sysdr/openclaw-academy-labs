# VERIFICATION - Lesson 01

Lesson: L01 - Install OpenClaw 2.0 inside a sandbox (Docker or VM)
Code: https://github.com/sysdr/openclaw-academy-labs-p/tree/main/L01-install-openclaw-2-0-inside-a-sandbox
Checked: 2026-10-17

## Version

- OpenClaw uses calendar versions (YYYY.M.patch). The docs release list labels **v2026.8.1 as "AKA OpenClaw 2.0"**: https://docs.openclaw.ai/releases/2026.8.1 (docs navigation, "Release notes").
- Latest stable on the GitHub releases page on 2026-10-17: **openclaw 2026.10.4**, released 16 Oct 2026, marked Latest (2026.10.10-beta.1 and 2026.10.5-beta.4 are pre-releases): https://github.com/openclaw/openclaw/releases
- npm: `openclaw@2026.10.4`, engines `node >=24.16.0 <25 || >=26.1.0`, release SHA `383c124`.
- Pinned image in this lesson: `ghcr.io/openclaw/openclaw:2026.10.4`.

## How this lesson was tested

- The sandbox could not reach ghcr.io or Docker Hub (HTTP 403 from the network allowlist), so the official image was **not** pulled.
- Instead, `openclaw@2026.10.4` was installed from npm under Node 24.22.0 and packaged into a local `FROM scratch` image (user `node`, uid 1000, `dist/docker-healthcheck.js` healthcheck, same `/app` layout). The npm package does not ship `docker-entrypoint.mjs`, so the official entrypoint (which runs `openclaw doctor --fix` before the Gateway) was not exercised.
- With that image, the lesson's real `docker/compose.yaml`, `setup.sh`, `run.sh` and `verify.sh` ran end to end on Docker Engine 29.8.2 / Compose v5.5.1, using `tests/fake_llm.py` as an OpenAI-compatible model: **11/11 PASS** (`tests/integration.sh`, "INTEGRATION PASS").
- The same OpenClaw build was also run directly on the host (no container) to observe the `/healthz` vs `/startupz` timing and the default exec policy.

## Commands, flags, keys and paths used (with sources)

OpenClaw Docker and CLI
- `ghcr.io/openclaw/openclaw:<version>` image, version-specific tags, `latest`; GHCR primary, Docker Hub mirror `openclaw/openclaw`: https://docs.openclaw.ai/install/docker
- Headless onboarding through the Gateway service: `docker compose run -T --rm --no-deps --entrypoint node openclaw-gateway dist/index.js onboard --non-interactive --accept-risk --skip-health --mode local --auth-choice openai-api-key --secret-input-mode ref --gateway-auth token --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN --skip-channels --no-install-daemon`: https://docs.openclaw.ai/install/docker (Headless bootstrap)
- `--gateway-bind lan`, `--custom-base-url`, `--custom-model-id`, `--custom-compatibility openai`, `--custom-text-input`, `--auth-choice custom-api-key`: `openclaw onboard --help` on 2026.10.4 (run locally). `CUSTOM_API_KEY` must be in the environment with `--secret-input-mode ref` (observed error message).
- Gateway command `node dist/index.js gateway --bind lan --port 18789`; bind modes `loopback|lan|tailnet|auto|custom`: upstream compose https://github.com/openclaw/openclaw/blob/main/docker-compose.yml and `openclaw gateway --help` on 2026.10.4.
- `gateway.bind` values, LAN vs loopback in Docker: https://docs.openclaw.ai/install/docker/networking-and-storage
- Compose environment pins `HOME`, `OPENCLAW_HOME`, `OPENCLAW_STATE_DIR`, `OPENCLAW_CONFIG_PATH`, `OPENCLAW_CONFIG_DIR`, `OPENCLAW_WORKSPACE_DIR`, `TZ`/`OPENCLAW_TZ`; mounts `/home/node/.openclaw`, `/home/node/.config/openclaw`; `cap_drop`, `no-new-privileges`, `init: true`, healthcheck `node dist/docker-healthcheck.js`: upstream docker-compose.yml.
- `OPENCLAW_IMAGE`, `OPENCLAW_GATEWAY_PORT` (host-published port; containers keep 18789 internally), `OPENCLAW_TZ`: https://docs.openclaw.ai/install/docker/environment-variables
- `OPENCLAW_GATEWAY_PORT: "18789"` pinned inside the container: lesson decision after observing the CLI dial the host port from inside the container (see If it breaks). Docs note dashboard commands inside containers use the internal listener port: https://docs.openclaw.ai/install/docker
- Image runs as `USER node` (uid 1000); built-in HEALTHCHECK; default bind loopback; `/healthz`, `/startupz`, `/readyz`: upstream Dockerfile https://github.com/openclaw/openclaw/blob/main/Dockerfile and https://docs.openclaw.ai/install/docker (Health checks)
- `openclaw agent --agent main --message ... --json --timeout <s>`, JSON `status`, `result.payloads[].text`, `runId`: https://docs.openclaw.ai/cli/agent (shape confirmed on 2026.10.4)
- `openclaw approvals get --gateway --json`, `openclaw approvals set --stdin` (JSON5), defaults `security`/`ask`/`askFallback`, values `deny|allowlist|full`, `off|on-miss|always`: https://docs.openclaw.ai/cli/approvals
- Default effective exec policy `security=full, ask=off`; stricter host policy wins: https://docs.openclaw.ai/tools/exec-approvals and observed `approvals get` output on 2026.10.4 ("stricter host security wins").
- Agent sandbox (`agents.defaults.sandbox`) requires the Docker socket in a Docker Gateway: comments in upstream docker-compose.yml; https://docs.openclaw.ai/install/docker/sandbox-and-troubleshooting
- State dir holds plaintext OAuth tokens in SQLite; treat as credentials: https://docs.openclaw.ai/install/docker/networking-and-storage
- Source image build needs at least 6 GB RAM: https://docs.openclaw.ai/install/docker (Prerequisites)

Docker and general practice (not OpenClaw behaviour)
- Published ports bypass ufw (nat table before INPUT): https://docs.docker.com/engine/network/packet-filtering-firewalls/
- `127.0.0.1:` host binding, do not expose docker.sock (`:ro` does not make the API read-only), non-root user, cap_drop, no-new-privileges, resource limits, read-only rootfs: https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html
- `docker compose` `profiles`, `env_file` with `path`/`required`, `mem_limit`, `pids_limit`, `read_only`, `tmpfs`: Compose spec https://docs.docker.com/reference/compose-file/services/
- Firecracker / Lambda isolation history: https://www.usenix.org/conference/nsdi20/presentation/agache, summary https://blog.acolyer.org/2020/03/02/firecracker/

## Observed on 2026.10.4 (lesson test runs)

- `/healthz` returned `{"ok":true,"status":"live"}` (200) at ~3 s uptime while `/startupz` returned 503 `{"status":"starting"}`; `/startupz` returned 200 `{"status":"started"}` at ~9.9 s.
- A second container sharing the state dir fails CLI calls with: "cannot verify Gateway ownership from this process (different PID namespace)". Running the CLI with `docker compose exec` inside the Gateway container works.
- With `.env` setting `OPENCLAW_GATEWAY_PORT=18799` and passed via `env_file`, the in-container CLI dialed `ws://127.0.0.1:18799` and failed with ECONNREFUSED.
- With `read_only: true` and only `/tmp` as tmpfs, startup failed: "Unable to create fallback OpenClaw temp dir: /home/node/.cache/openclaw-1000". Adding a uid-1000 tmpfs at `/home/node/.cache` fixed it (solution/).

## [VERIFY] items (6 total: 1 shown in the article, 1 in solution/README.md)

1. [VERIFY: the `2026.10.4` tag is published at ghcr.io/openclaw/openclaw] Docs confirm version-specific tags exist; this exact tag could not be pulled from the test sandbox. Check: `docker pull ghcr.io/openclaw/openclaw:2026.10.4`. (In article.)
2. [VERIFY: the official image entrypoint (`docker-entrypoint.mjs`, runs `openclaw doctor --fix`) starts under `cap_drop: [ALL]`] Not present in the npm package, so untested. Check: `make run`, then `make verify`.
3. [VERIFY: no path outside `/tmp`, `/home/node/.cache` and `/home/node/.openclaw.update-captures` is written under `read_only: true` with the official image, on first start and after an image upgrade] (In solution/README.md.)
4. [VERIFY: `--auth-choice openai-api-key` with `--secret-input-mode ref` completes a live OpenAI turn] Documented in the Docker guide's headless bootstrap; only the custom provider path was run live.
5. [VERIFY: provider console wording for restricted, inference-only API keys] README says "if your provider offers restricted keys"; no provider-specific claim made.
6. [VERIFY: macOS Docker Desktop and WSL2 bind-mount ownership] `setup.sh` checks uid 1000 ownership only on Linux. Check on macOS that `make setup` and `make run` write `state/` without permission errors.

## Quality gates (run 2026-10-17)

- shellcheck (0.11.0, via shellcheck-py) on scripts/*.sh, tests/*.sh, tests/mock/*: clean.
- JSON/YAML valid: fixtures/cases.json parsed; `docker compose config --quiet` passed; tests/compose.fake-llm.yaml parsed by Compose in the integration run.
- Unit tests: `python3 -m unittest`: 15 tests OK.
- Mock end-to-end (real verify.sh vs mock docker/curl): pass state 11/11 PASS exit 0; fail state 4/11 PASS exit 1; matches expected/verify.txt (4/4 PASS).
- Integration (real OpenClaw 2026.10.4 code in a container + fake model): 11/11 PASS.
- Read-only solution overlay: 11/11 PASS with `ReadonlyRootfs=true`; assignment edits applied in a scratch copy: unit + mock e2e green with 12 checks.
- Scripts executable: yes. Zip: excludes .git, .env, node_modules, caches, reports, state; under 30 files and 1 MB; FOLDER/ at zip root (see final listing in the delivery message).

## Self-check

- Every command and key sourced? Yes (above); unverifiable items marked [VERIFY].
- verify.sh tests PROOF exactly? Yes: check 11 sends the first message through the Gateway inside the sandbox and requires a fresh token in the reply; checks 1 to 10 prove "sandboxed".
- Prose 800 words or fewer? Yes: 775 words excluding code blocks, inline commands, diagram captions and Sources (757 if headings and meta line are also excluded).
- 2 to 3 sourced Field Notes? Yes, 3: Docker publishing vs ufw (Docker docs, OWASP), docker.sock (OWASP), Firecracker (USENIX NSDI 2020).
- Opens from PREVIOUS and bridges to NEXT? L01 has no previous; the article says so. Bridges to L02 in Next up.
- Diagrams pass validation and PNGs look clean? Yes: fit rule, 48 px sibling spacing, 28 px insets, 40 px margins, <= 4 color roles, text >= 22 px; PNGs at 1600 px inspected, annotation curves rerouted around boxes.
- Title reads "Lesson NN - TITLE"? Yes.
- Article free of Portfolio checkpoint, commit command, resume line, Get the code section, GitHub link and clone commands? Yes.
- No banned phrases, two em dashes at most? Yes, 0 em dashes.
- Would a senior engineer learn something? Yes: the ufw bypass, `:ro` docker.sock, the PID-namespace ownership check, the host-port leak into the container, and the measured liveness/readiness gap are all non-obvious and testable.
