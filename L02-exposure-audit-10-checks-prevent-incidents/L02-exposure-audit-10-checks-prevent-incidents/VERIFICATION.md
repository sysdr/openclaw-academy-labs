# VERIFICATION - Lesson 02

- Lesson: L02, Exposure audit: the 10 checks that prevent most incidents (Paid)
- Code: https://github.com/sysdr/openclaw-academy-labs-p/tree/main/L02-exposure-audit-10-checks-prevent-incidents
- Verified on: OpenClaw **2026.10.5** (`1b58cb9`), the npm `latest` dist-tag on 21 Oct 2026 (published 18 Oct 2026). Docker Engine 29.9.1, Compose v5.6.0, Python 3.13, Node 24.22, shellcheck 0.11.0, Linux.
- Version source: `npm view openclaw dist-tags` (latest 2026.10.5, extended-stable 2026.9.33, beta 2026.10.10-beta.3); GitHub releases https://github.com/openclaw/openclaw/releases. Lesson 01 pinned 2026.10.4; this lesson bumps the pin, and check 10 enforces it.

## How it was tested

- The registry (ghcr.io and Docker Hub) was unreachable from the build sandbox. As in Lesson 01, the image was emulated: the published npm package `openclaw@2026.10.5` plus Node 24.22 on a minimal root filesystem, tagged `ghcr.io/openclaw/openclaw:2026.10.5`, user `node` (uid 1000), workdir `/app`. OpenClaw code is the real release; the image wrapper is not.
- With that image, the real `bootstrap.sh`, `build.sh`, `run.sh`, `verify.sh`, `setup.sh` and `demo.sh` ran end to end:
  - Lesson 01 baseline: **8/10 PASS** (checks 3 and 4 fail on real OpenClaw findings).
  - After `make setup`: **10/10 PASS**, exit 0, report written (`reports/verify-20261021T093649Z.txt`).
  - Demo: drift to `discovery.mdns.mode=full` gives 9/10 (`discovery.mdns_full_mode`, critical); restored gives 10/10.
  - `tests/integration.sh` repeats the whole sequence in a throwaway copy on port 18799: **INTEGRATION PASS**.
  - `solution/drift.sh`: `--save` then `no drift`; after the mDNS flip, `DRIFT DETECTED` with `new finding: discovery.mdns_full_mode`; after restore, `no drift`.
- The OpenClaw CLI was also run directly on the host (Node 24) to capture audit and approvals output for several configs. `fixtures/cases.json` holds that real output.

## Commands, flags, keys and paths (with sources)

OpenClaw CLI
- `openclaw security audit`, `--json`, `--deep`, `--fix`; JSON fields `summary.{critical,warn,info}`, `findings[].{checkId,severity,title,detail,remediation}`, `suppressedFindings`; `security.audit.suppressions[]` with `checkId`, `detailIncludes`, `titleIncludes`, `reason`; what `--fix` does and does not change: https://docs.openclaw.ai/cli/security
- checkIds used, all observed in real 2026.10.5 output: `gateway.loopback_no_auth`, `gateway.bind_no_auth`, `gateway.http.no_auth`, `gateway.control_ui.allowed_origins_required`, `gateway.auth_no_rate_limit`, `gateway.trusted_proxies_missing`, `discovery.mdns_full_mode`, `config.insecure_or_dangerous_flags`, `fs.state_dir.perms_readable`, `fs.config.perms_world_readable`, `summary.attack_surface`. `config.insecure_or_dangerous_flags` and the mDNS/auth findings are also named in https://docs.openclaw.ai/cli/security
- Observed, not documented: `openclaw security audit --json` exits 0 with 5 critical findings (2026.10.5). The script never relies on the exit code.
- Observed: on a default install `openclaw approvals get --json` reports `security.effective=full`, `ask.effective=off`, `askFallback.effective=deny`, and the security audit raises no finding about it.
- `openclaw approvals get --json` (fields `effectivePolicy.scopes[].{agentId,security.effective,ask.effective,askFallback.effective}`), `openclaw approvals set --stdin|--file`: https://docs.openclaw.ai/cli/approvals and `openclaw approvals --help` on 2026.10.5. Exec policy values `deny`, `on-miss`, `deny`: Lesson 01 VERIFICATION (https://docs.openclaw.ai/tools/exec-approvals), re-run here.
- `openclaw config get <path>` (`--json`; unset paths print an error envelope and exit 1, observed), `config set`, `config patch --stdin` (JSON5, objects merge), `config validate`, `config file`, `config schema`: https://docs.openclaw.ai/cli/config and `--help` on 2026.10.5.
- Config keys, all present in `openclaw config schema` on 2026.10.5 and applied successfully: `gateway.mode`, `gateway.bind` (`auto|lan|loopback|custom|...`), `gateway.auth.mode` (`token|password|none`), `gateway.auth.rateLimit.{maxAttempts,windowMs,lockoutMs}` (values from the audit's own remediation text), `gateway.controlUi.allowedOrigins` (from the `allowed_origins_required` remediation text), `discovery.mdns.mode` (`off|minimal|full`, schema description), `browser.ssrfPolicy.dangerouslyAllowPrivateNetwork`, `security.audit.suppressions`.
- `OPENCLAW_GATEWAY_TOKEN` as the token source for `gateway.auth.mode=token`: https://docs.openclaw.ai/cli/security (names `gateway.auth.token` / `OPENCLAW_GATEWAY_TOKEN`).
- `openclaw --version` output format `OpenClaw 2026.10.5 (1b58cb9)`: observed.
- Config writes from a second container while the gateway runs fail with `GatewayLockNamespaceError` (different PID namespace): observed on 2026.10.5; Lesson 01 hit the same lock. Scripts use `docker compose exec` when the gateway is up.

Docker (unchanged from Lesson 01 except the pin)
- Image `ghcr.io/openclaw/openclaw:<version>`, gateway command `node dist/index.js gateway --bind lan --port 18789`, healthcheck `node dist/docker-healthcheck.js`, env `OPENCLAW_STATE_DIR`, `OPENCLAW_CONFIG_PATH`, `OPENCLAW_GATEWAY_PORT`: https://docs.openclaw.ai/install/docker and upstream https://github.com/openclaw/openclaw/blob/main/docker-compose.yml (via Lesson 01).
- `docker port <container> 18789`: https://docs.docker.com/reference/cli/docker/container/port/
- `docker inspect` fields `Config.User`, `Config.Image`, `HostConfig.{Privileged,CapAdd,CapDrop,SecurityOpt,NetworkMode,PidMode,IpcMode}`, `Mounts[].{Type,Source}`: https://docs.docker.com/reference/cli/docker/inspect/ and observed output.
- `docker compose --progress quiet`, `ps -q`, `exec -T`, `run --rm --no-deps -T`, `-p <project> down`, `COMPOSE_PROJECT_NAME`: https://docs.docker.com/reference/cli/docker/compose/

Real-world references
- STRIKE exposure counts (40,000+ at report, 135,000+ at writing; 12,812 then 50,000+ vulnerable to a patched RCE; default bind 0.0.0.0:18789 as reported): https://www.theregister.com/2026/02/09/openclaw_instances_exposed_vibe_code/
- CVE-2026-25253, fixed in 2026.1.29 (check 10's floor): https://osv.dev/vulnerability/CVE-2026-25253
- Capital One 2019 SSRF via misconfigured WAF to the metadata service, over-privileged credentials: https://krebsonsecurity.com/2019/08/what-we-can-learn-from-the-capital-one-hack/
- Non-actionable alerts get ignored: https://sre.google/sre-book/monitoring-distributed-systems/
- Controllers compare desired and current state: https://kubernetes.io/docs/concepts/architecture/controller/

## [VERIFY] items

1. [VERIFY: `ghcr.io/openclaw/openclaw:2026.10.5` is published and its default user is uid 1000 `node`] Registry unreachable from the sandbox; tested with an emulated image built from the real npm package.
2. [VERIFY: the official image's entrypoint behaves the same with this compose `command:`] The npm package has no `docker-entrypoint.mjs`; Lesson 01 noted the same gap.
3. [VERIFY: Lesson 01's compose project is named `openclaw-l01`, so `docker compose -p openclaw-l01 down` stops it] Inferred from Lesson 01's container name `openclaw-l01-openclaw-gateway`.
4. [VERIFY: scripts on macOS (BSD userland, Docker Desktop) and WSL2] Written to be portable (python for file modes, curl/python fallback, no GNU-only flags) but run only on Linux.

## Quality gates (run 21 Oct 2026)

- shellcheck 0.11.0 on `scripts/*.sh tests/*.sh solution/*.sh`: clean
- JSON valid: `fixtures/cases.json`, `config/exec-approvals.json`; JSON5 patch accepted by `openclaw config patch` and `config validate`; compose valid (`docker compose config --quiet`)
- Unit tests: 15/15 OK (`python3 -m unittest discover -s tests`)
- Mock end-to-end (real `verify.sh` against `tests/mock/docker`, passing and failing): 7/7 PASS
- Integration (emulated image): INTEGRATION PASS
- All scripts executable; zip excludes `.git`, `.env`, `node_modules`, caches and `reports/`; 29 files, 34 KB, `L02-exposure-audit-10-checks-prevent-incidents/` at the zip root; tested by unzipping into an empty folder and rerunning unit, mock end-to-end and shellcheck.

## Self-check

- Every command and key sourced? **Yes** (four items marked [VERIFY] above).
- verify.sh tests PROOF exactly? **Yes**: it passes only when the last audit line is `10/10 PASS`, exits 0 only then, writes `reports/verify-<time>.txt`.
- Prose 800 words or fewer? **Yes** (792).
- 2-3 sourced Field Notes? **Yes** (3: The Register/STRIKE, Krebs/Capital One, Google SRE book).
- Opens from PREVIOUS and bridges to NEXT? **Yes**.
- Diagrams pass validation and the PNGs look clean? **Yes** (fit, sibling spacing, bounds, arrow/text crossings checked by script; PNGs inspected at 1600 px).
- Title reads "Lesson NN - TITLE"? **Yes**.
- Article free of Portfolio checkpoint, commit command, resume line, Get the code section, GitHub link and clone commands? **Yes**.
- No banned phrases, two em dashes at most? **Yes** (0 em dashes).
- Would a senior engineer learn something? **Yes**: OpenClaw's own audit exits 0 on criticals, misses a default `security=full` exec policy, and raises a false critical on a correctly published container; the three-vantage-point design catches all three.
