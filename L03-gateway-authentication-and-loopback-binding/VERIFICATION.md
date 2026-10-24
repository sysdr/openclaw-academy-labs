# VERIFICATION - L03 Gateway authentication and loopback binding

Lesson code: https://github.com/sysdr/openclaw-academy-labs-p/tree/main/L03-gateway-authentication-and-loopback-binding
Researched: 2026-10-24.

## Version

- Target: **OpenClaw v2026.10.6**. OpenClaw uses calendar versions; the docs release list labels v2026.8.1 "AKA OpenClaw 2.0", so the "2.x" line is 2026.8.1 and later. Source: https://docs.openclaw.ai/releases/2026.10.6
- Note: the GitHub releases page fetched the same day marked v2026.10.4 as "Latest" (newer patches may not be mirrored there yet). Nothing in this lesson depends on a 10.4 to 10.6 change. https://github.com/openclaw/openclaw/releases

## Commands, flags, keys, paths and env vars used (with sources)

| Item | Used in | Source |
| --- | --- | --- |
| Config file `~/.openclaw/openclaw.json`, JSON5, strict validation, unknown keys refuse startup | setup, verify, build | https://docs.openclaw.ai/gateway/configuration |
| `OPENCLAW_CONFIG_PATH` | lib.sh, tests | https://docs.openclaw.ai/gateway/configuration |
| `openclaw config set <path> <value>`, `openclaw config unset <path>` | setup.sh | https://docs.openclaw.ai/gateway/configuration |
| `openclaw doctor` (exit code 78 on invalid config) | article "If it breaks" | https://docs.openclaw.ai/gateway/configuration , https://docs.openclaw.ai/cli/gateway/running |
| `gateway.mode: "local"` required to start | config fragment, setup | https://docs.openclaw.ai/gateway/config-gateway , https://docs.openclaw.ai/cli/gateway/running |
| `gateway.port` default 18789; precedence `--port` > `OPENCLAW_GATEWAY_PORT` > `gateway.port` > 18789 | lib.sh `resolve_port` | https://docs.openclaw.ai/gateway/config-gateway |
| `gateway.bind` values `auto/loopback/lan/tailnet/custom`; `loopback` default on regular hosts; detected container with bind unset resolves `auto` to 0.0.0.0 | config, verify 01 | https://docs.openclaw.ai/gateway/config-gateway , https://docs.openclaw.ai/gateway/security/network-exposure |
| `gateway.auth.mode` values `none/token/password/trusted-proxy` | config, verify 02 | https://docs.openclaw.ai/gateway/config-gateway |
| `mode="token"` uses `gateway.auth.token` or `OPENCLAW_GATEWAY_TOKEN` | config, .env, run.sh | https://docs.openclaw.ai/gateway/tools-invoke-http-api |
| `gateway.auth.rateLimit.{maxAttempts,windowMs,lockoutMs,exemptLoopback}`, `exemptLoopback` default true | config fragment | https://docs.openclaw.ai/gateway/config-gateway |
| Non-loopback bind without auth is blocked (fails closed) | article | https://docs.openclaw.ai/cli/gateway/running , https://docs.openclaw.ai/gateway/security/network-exposure |
| Startup rejects blank/placeholder tokens; audit warns under 24 chars; `openssl rand -hex 32` suggested | setup.sh, verify 04 | https://docs.openclaw.ai/gateway/security/network-exposure |
| `openclaw gateway run`, `--bind`, `--auth`, `--port`; `--token` defaults to `OPENCLAW_GATEWAY_TOKEN` | run.sh | https://docs.openclaw.ai/cli/gateway/running |
| `openclaw gateway stop` | article Run step | https://docs.openclaw.ai/cli/gateway/running (service commands), https://docs.openclaw.ai/releases/2026.10.6 |
| `GET /health` unauthenticated, 200 `{"ok":true,"status":"live"}`; `/healthz` alias | verify 07-08, mock | https://docs.openclaw.ai/gateway/health |
| `POST /tools/invoke`, `Authorization: Bearer`, 401 unauthorized, 403/404 policy, 429 rate-limited; body `{tool, action, args}` | verify 09-10, mock, solution | https://docs.openclaw.ai/gateway/tools-invoke-http-api |
| Shared-secret bearer = full operator scopes (`operator.admin`, `.approvals`, `.pairing`, `.read`, `.talk.secrets`, `.write`) | README "Token scope" | https://docs.openclaw.ai/gateway/tools-invoke-http-api , https://docs.openclaw.ai/gateway/security/network-exposure |
| Env credential changes require a Gateway restart | solution/rotate-token.sh | https://docs.openclaw.ai/gateway/security/network-exposure |
| `openclaw security audit` | bootstrap.sh (L02 fallback) | https://docs.openclaw.ai/cli/security |
| Docker: service `openclaw-gateway`, setup defaults `OPENCLAW_GATEWAY_BIND=lan`, `loopback` inside a container is unreachable from the host | docker/compose.loopback.yml, config/README | https://docs.openclaw.ai/install/docker , https://docs.openclaw.ai/install/docker/networking-and-storage |
| Docker `-p` publishes to all interfaces by default; `127.0.0.1:` prefix restricts; pre-28.0.0 L2 caveat | article field note | https://docs.docker.com/engine/network/port-publishing/ |
| Compose `ports` merge keeps both mappings; `!override` needs Compose 2.24.4+ | docker/compose.loopback.yml, field note | https://docs.docker.com/reference/compose-file/merge/ |
| `curl -H @-` reads headers from stdin | verify 10, demo, solution | curl manual: https://curl.se/docs/manpage.html#-H |

## Real-world references

- ClawJacked (Oasis Security), fixed in 2026.2.26: https://www.bleepingcomputer.com/news/security/clawjacked-attack-let-malicious-websites-hijack-openclaw-to-steal-data/
- SecurityScorecard scan, 28,663 unique IPs with exposed OpenClaw control panels: https://www.techzine.eu/news/security/138633/over-40000-openclaw-agents-vulnerable/
- moby/moby#45610: https://github.com/moby/moby/issues/45610

## [VERIFY] items (6)

1. [VERIFY: which wins when both a literal `gateway.auth.token` and `OPENCLAW_GATEWAY_TOKEN` are set] The docs say token mode uses one "or" the other without stating precedence. setup.sh removes the literal token (with confirmation) so the question never arises.
2. [VERIFY: `openclaw config set` exit code and output on v2026.10.6] setup.sh only relies on exit status; output is discarded.
3. [VERIFY: the host address in the official `docker-compose.yml` `ports:` entry] Not shown in the docs fetched. `compose.loopback.yml` replaces it with `!override` either way.
4. [VERIFY: the status a valid token gets for `sessions_list` on a fresh install] verify.sh accepts 200/400/403/404 (all mean auth passed) and fails only on 401/429/no response.
5. [VERIFY: how an L01 service-installed Gateway receives `OPENCLAW_GATEWAY_TOKEN`] run.sh uses a foreground Gateway; the article tells readers to `openclaw gateway stop` the service first.
6. [VERIFY: whether `bind: loopback` also opens `::1`] verify.sh accepts `127.0.0.0/8` and `::1`, so either result passes.

## Quality gates (run 2026-10-24 in the build sandbox)

- shellcheck 0.x via shellcheck-py: `shellcheck -x scripts/*.sh solution/*.sh` clean.
- JSON5 fixtures and config fragment parse (`src/gwcheck.py`); `docker/compose.loopback.yml` parses as YAML (custom `!override` tag).
- Unit tests: 10 passed. Mock end-to-end tests: 2 passed. Live integration tests: 2 skipped (no OpenClaw in sandbox).
- Mock end-to-end: real `verify.sh` against `tests/mock_gateway.py` gives `10/10 PASS` exit 0 (loopback + token) and `3/10 PASS (7 FAIL)` exit 1 (0.0.0.0 + any caller + literal token).
- `solution/rotate-token.sh` against the mock: `3/3 PASS`. `scripts/demo.sh` against the mock: all five steps as described.
- Listener lookup used `lsof` (no `ss`/`netstat` in sandbox); the `/proc/net/tcp` fallback is covered by a unit test.
- Scripts executable; zip excludes .git, .env, caches, reports. Zip: 28 files under `L03-gateway-authentication-and-loopback-binding/`, 35 KB.
- Diagrams: validator (fit rule, 48 px sibling spacing, 28 px parent padding, 40 px margin, min 22 px font, <=4 colour roles, title/desc, white background first) passes for all three; PNGs exported at 1600 px and inspected.

## Self-check

- Every command and key sourced? **Yes** (6 items marked [VERIFY] where docs were silent).
- verify.sh tests PROOF exactly? **Yes**: loopback listener, LAN refusal on every local address, 401 without/with wrong token, token accepted.
- Prose 800 words or fewer? **Yes** (785, excluding code, commands, output, captions, Sources).
- 2-3 sourced Field Notes? **Yes**, 3.
- Opens from PREVIOUS and bridges to NEXT? **Yes** (L02 audit; L04 exec approvals).
- Diagrams pass validation and PNGs look clean? **Yes.**
- Title reads "Lesson 03 - Gateway authentication and loopback binding"? **Yes.**
- Article free of Portfolio checkpoint, commit command, resume line, Get the code section, GitHub link, clone commands? **Yes.**
- No banned phrases, two em dashes at most? **Yes** (0 em dashes).
- Would a senior engineer learn something? **Yes**: Compose `ports` merging keeps the 0.0.0.0 mapping, the pre-28.0 Docker L2 caveat, and loopback as a machine boundary rather than a program boundary.
