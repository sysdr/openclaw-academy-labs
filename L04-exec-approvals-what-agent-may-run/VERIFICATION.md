# VERIFICATION - L04 Exec approvals: scope exactly what your agent may run

- Lesson: L04 · M1 Ship it safely · Paid
- Folder: `L04-exec-approvals-what-agent-may-run`
- CODE_URL: https://github.com/sysdr/openclaw-academy-labs-p/tree/main/L04-exec-approvals-what-agent-may-run
- Verified on: OpenClaw 2026.10.7 (157d8c2) from npm (`latest` tag on 2026-10-27), Node 24.22.1, Python 3.13.17, Ubuntu 24.04.5 (merged /usr)
- Proof achieved: yes. Live run: `make verify` → `21/21 PASS` (see `expected/verify-pass.txt`). Live negative run with `fixtures/approvals-loose.json` → `4/20 PASS`, exit 1. Assignment solution live → `26/26 PASS`.

## Commands, keys and paths used, with sources

"Observed" means run on 2026.10.7 in the build sandbox, output captured.

OpenClaw docs: exec approvals - https://docs.openclaw.ai/tools/exec-approvals
- `defaults` / `agents.<id>` with `security` (`deny|allowlist|full`), `ask` (`off|on-miss|always`), `askFallback` (`deny|allowlist|full`), `autoAllowSkills`. Observed via `openclaw approvals get --json`.
- `allowlist[].pattern` glob over resolved binary path or bare PATH name; `allowlist[].argPattern` ECMAScript regex over args joined by single spaces, argv[0] excluded. Observed: `/bin/ls` entry denied `ls` and `/bin/ls`; `/usr/bin/ls` allowed both. Unanchored `argPattern: "status"` allowed `git -c core.pager=cat status`; anchored version denied it.
- Effective policy is the stricter of `tools.exec.*` and host approvals; approvals can tighten but not loosen. Observed in `effectivePolicy.scopes[].security.note` ("stricter host security wins").
- Default `security=full`, `ask=off` on gateway hosts. Observed on a fresh state dir.
- Storage in `exec_approvals_config` row of `~/.openclaw/state/openclaw.sqlite`; legacy JSON imported by `openclaw doctor --fix`. Observed path in `approvals get --json` `.path`.
- Denial messages `Exec denied (...)`, `SYSTEM_RUN_DENIED`, `Exec policy unavailable`. Observed: `Exec denied (SYSTEM_RUN_DENIED: approval cannot safely bind this command)` for redirection; `exec denied: Headless runs cannot wait for interactive exec approval.` for allowlist misses from `openclaw agent`.
- `tools.exec.strictInlineEval` boolean. Observed accepted by `openclaw config set`.
- Entries generated before 2026.8.1 inactive after upgrade (basis for the minimum version).

OpenClaw docs: exec approvals advanced - https://docs.openclaw.ai/tools/exec-approvals-advanced
- Chains need every segment allowlisted; redirections unsupported in allowlist mode. Observed: `uptime && touch canary` and `uptime > canary` denied, canary absent.
- Pending approvals expire after 30 minutes by default; `askFallback` applies when no approval UI accepts the request.
- `safeBins` defaults (`cut uniq head tail tr wc`), not used in this lesson.

OpenClaw docs: approvals CLI - https://docs.openclaw.ai/cli/approvals
- `openclaw approvals get [--json]`, `openclaw approvals set --file <path>`, `openclaw approvals allowlist add --agent <id> "<pattern>"`, `openclaw exec-policy show [--verbose]`. All observed; `--help` output matches.
- `approvals set` replaces the document (CLI help: "Replace exec approvals with a JSON file"). Observed.

OpenClaw docs: custom providers - https://docs.openclaw.ai/concepts/model-providers/custom-providers
- `models.providers.<id>.baseUrl`, `api: "openai-completions"`, `models[].id/name/reasoning/input/contextWindow/maxTokens`. Observed: provider without `apiKey` accepted and used via `openclaw agent --model probe/exec-probe`. (`auth: "none"` from the docs page was rejected by 2026.10.7 schema: allowed values `api-key|aws-sdk|oauth|token`; so the lab omits auth.)

OpenClaw CLI (observed `--help` on 2026.10.7, docs index https://docs.openclaw.ai/cli)
- `openclaw --version` → `OpenClaw 2026.10.7 (157d8c2)`
- `openclaw health --json` → `{"ok": true, ...}`
- `openclaw config get tools.exec --json`, `openclaw config set <key> <value>`, `openclaw config patch --file|--stdin [--dry-run] [--json]`; `null` deletes a path.
- `openclaw agent --agent <id> --model <provider/model> --session-key <key> --message <text> --json --timeout <s>`
- `openclaw gateway run --bind loopback --auth token`; token from `OPENCLAW_GATEWAY_TOKEN`.
- `gateway.mode`, `gateway.bind`, `gateway.auth.mode` accepted by `config patch --dry-run`.
- `openclaw nodes invoke --command system.run` is refused ("reserved for shell execution; use the exec tool"), which is why the lab drives the exec tool through a scripted model.

Release/version - https://github.com/openclaw/openclaw/releases , npm `openclaw` dist-tags (latest 2026.10.7, extended-stable 2026.9.35). 2026.10.7 requires Node >=24.22.1 <25 or >=26.12.1 (observed install error on Node 22).

External sources used in Field Notes
- AWS IAM permissions boundaries (intersection of policies): https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html
- Merged /usr layout: https://wiki.gentoo.org/wiki/Merge-usr (plus observed `/bin -> usr/bin` on Ubuntu 24.04)
- git shell escapes: https://gtfobins.org/gtfobins/git/
- LangGraph interrupts (Transfer note): https://docs.langchain.com/oss/python/langgraph/interrupts

## [VERIFY] items (4)

1. [VERIFY: replace the Lesson 03 link in article.md (currently the newsletter home) with the published L03 post URL]
2. [VERIFY: run `make verify` inside the exact L01 Docker image; this build ran on an Ubuntu 24.04 sandbox with the gateway as a foreground process, not the L01 container]
3. [VERIFY: scripts on macOS and WSL2; written for portability (bash, python3 socket check, no ss/lsof/jq) but only run on Linux. On macOS `ls` is `/bin/ls`, so edit the allowlist; verify.sh flags missing paths]
4. [VERIFY: GitHub Releases marks 2026.10.4 as Latest while npm `latest` is 2026.10.7; confirm which one readers will get from the L01 install method]

## Quality gates (run 2026-10-27)

- shellcheck -x scripts/*.sh tests/e2e_mock.sh: clean (ShellCheck 0.11.0)
- JSON valid: config/*.json, fixtures/*.json, solution/*.json (python -m json.tool via `make build`): PASS
- Unit tests: 9 passed, 1 skipped without OpenClaw; live integration test (`L04_LIVE=1`): PASS
- Mock end-to-end (`tests/e2e_mock.sh`): pass state exit 0 all PASS; fail state exit 1 with canary caught
- Live verify: 21/21 PASS; live loose policy: 4/20 PASS (exit 1); live solution: 26/26 PASS
- Scripts executable: yes
- Zip: FOLDER/ at root, excludes .git/.env/node_modules/caches/reports/.state, 29 files, 36 KB

## Self-check

- Every command and key sourced? yes (docs URL or observed on 2026.10.7; one docs value, `auth: "none"`, contradicted by the schema and not used)
- verify.sh tests PROOF exactly? yes (allowlist config live + denied commands refused by the real exec tool, side effects checked)
- Prose 800 words or fewer? yes (772, excluding code blocks, inline code, captions and Sources)
- 2-3 sourced Field Notes? yes (3)
- Opens from PREVIOUS and bridges to NEXT? yes
- Diagrams pass validation and the PNGs look clean? yes (validator: fit rule, 48px spacing, text overlap, bounds; PNGs inspected at 1600px)
- Title reads "Lesson NN - TITLE"? yes
- Article free of Portfolio checkpoint, commit command, resume line, Get the code section, GitHub link and clone commands? yes (the only GitHub link is the OpenClaw releases page, a source)
- No banned phrases, two em dashes at most? yes (0 em dashes)
- Would a senior engineer learn something? yes: resolved-path matching on merged /usr, unanchored argPattern bypass reproduced live, and the default full/off policy on a fresh install
