# VERIFICATION - L05 Your first skill, written to spec

Code: https://github.com/sysdr/openclaw-academy-labs-p/tree/main/L05-your-first-skill-written-to-spec

## Environment actually used

- OpenClaw 2026.10.7 (157d8c2), installed with `npm i -g openclaw@2026.10.7` (npm dist-tag `latest` on 2026-10-27; `engines.node` is `>=24.22.1 <25 || >=26.12.1`)
- Node 24.22.1, Python 3.13, Linux 6.18 (Ubuntu userland, sandbox VM), bash 5
- State created with `openclaw setup --baseline`, then the L03/L04 end state via `scripts/bootstrap.sh`
- Gateway: `openclaw gateway run --bind loopback --auth token`, token from `OPENCLAW_GATEWAY_TOKEN`

## Proof status

Achieved on this version. `make verify` printed `16/16 PASS` against a live gateway (report: `reports/verify-<timestamp>.txt`).
The model step in Part C is a scripted local model (`src/probe_model.py`), so C2-C4 prove that OpenClaw delivers the
skill and runs its command, not that a real LLM chooses it. Part D (`LIVE_MODEL=...`) covers that and was not run here.

## Commands, keys and paths, with sources

OpenClaw docs: Skills - https://docs.openclaw.ai/tools/skills
- Skill = directory with `SKILL.md`, YAML frontmatter plus markdown body. Observed.
- Precedence: `<workspace>/skills` highest, then `<workspace>/.agents/skills`, `~/.agents/skills`, `<state-dir>/skills`, workshop, bundled, `skills.load.extraDirs`. Observed `source: openclaw-workspace` for `<workspace>/skills/uptime-report`.
- Name and slash command come from frontmatter `name` (folder path is organisation only). Observed: `l05-dir-mismatch/` with `name: l05-other-name` listed as `l05-other-name`.
- Invalid skill files are reported and skipped. Observed in gateway log: `Skipping invalid skill: ... error=description is required` and `... invalid frontmatter: BAD_INDENT ...`. Not shown by `skills list` or `skills check`.
- Optional keys `user-invocable`, `disable-model-invocation`, `command-dispatch`, `command-tool`, `command-arg-mode`, `homepage`. Used as the linter's known-key set.
- `metadata.openclaw.requires.bins`, `os`, `always`, `primaryEnv`, `skillKey`. Used: `requires.bins`, `os`. Observed: missing bin gives `eligible: false`, `missing.bins: ["l05-no-such-binary"]`.
- Frontmatter parsed as YAML; metadata re-parsed as JSON5; multi-line metadata accepted. The lesson's single-line strict-JSON rule (R6) is a lesson rule, stricter than OpenClaw.
- `{baseDir}` placeholder. Not used.
- Inventory / readiness / visibility definitions. Used for Part B labels.
- Prompt injection as compact XML `<available_skills>` with name, description, location. Observed in the captured system prompt.
- Token impact: ~97 chars per skill plus field lengths. Observed: uptime-report entry is exactly 246 chars = 97 + 13 + 85 + 51.
- `skills_read({ name })` loads the full SKILL.md. Observed: reachable through the `tool_call` tool with `{"id": "skills_read"}`; result contained the body.
- Explicit `$skill-name` reference: OpenClaw tells the model to read the referenced SKILL.md. Observed text: "Use the following explicitly referenced skills for this request. Read each skill's SKILL.md before acting:".
- Agent allowlists are not a host shell authorization boundary. Basis for the assignment (activation does not grant exec).
- Snapshots: watcher on by default; new sessions recheck. Observed: new workspace skill visible to `skills info` within ~2 s; verify.sh polls up to 30 s.

OpenClaw docs: Creating skills - https://docs.openclaw.ai/tools/creating-skills
- Workspace path `~/.openclaw/workspace/skills/<name>/SKILL.md`. Observed (workspace from `skills check` `.workspaceDir`).
- `name`: lowercase letters, digits, hyphens; keep folder and `name` aligned; `description` one line, under 160 characters. Linter rules R3, R4, R5. Note: 2026.10.7 does not enforce R3/R4 (observed loading `L05_Bad_Case`).
- Test with `openclaw agent --message "..."`. Used.

OpenClaw docs: Skills CLI - https://docs.openclaw.ai/cli/skills
- `openclaw skills info <name> --json [--agent <id>]`. Observed fields: `source`, `filePath`, `eligible`, `modelVisible`, `missing.{bins,anyBins,env,config,os}`, `requirements`.
- `openclaw skills check --agent <id> --json`. Observed keys: `workspaceDir`, `summary`, `eligible`, `modelVisible`, `commandVisible`, `missingRequirements`.
- `openclaw skills list --json`. Observed shape `{workspaceDir, managedSkillsDir, skills: [...]}`.

OpenClaw docs: Exec approvals and CLI (reused from L04) - https://docs.openclaw.ai/tools/exec-approvals, https://docs.openclaw.ai/cli/approvals
- `openclaw approvals get --json` (`.file.agents.main.allowlist[].pattern`), `openclaw approvals set --file <path>` (replaces the document). Observed.
- `tools.exec.security`, `tools.exec.ask`, `tools.exec.strictInlineEval` via `openclaw config set`. Observed.
- Denial text observed for `who`: `exec denied: Headless runs cannot wait for interactive exec approval. Effective host exec policy: security=allowlist ask=on-miss askFallback=deny`.

OpenClaw docs: custom providers - https://docs.openclaw.ai/concepts/model-providers/custom-providers
- `models.providers.<id>.baseUrl`, `api: "openai-completions"`, `models[].{id,name,reasoning,input,contextWindow,maxTokens}`. Observed accepted by `openclaw config patch --file` and `--dry-run`; used via `--model probe/skill-probe`.

OpenClaw CLI (observed `--help` and behaviour on 2026.10.7; index https://docs.openclaw.ai/cli)
- `openclaw --version` -> `OpenClaw 2026.10.7 (157d8c2)`
- `openclaw setup --baseline`, `openclaw health --json` (`"ok": true`)
- `openclaw config get <path> [--json]`, `openclaw config set <path> <value>`, `openclaw config patch --file <f> [--dry-run]`
- `openclaw agent --agent <id> --model <provider/model> --session-key <k> --message <m> --json --timeout <s>`; reply at `.result.meta.terminalReply.text`
- `openclaw gateway run --bind loopback --auth token`

Release channel - https://github.com/openclaw/openclaw/releases, https://docs.openclaw.ai/reference/RELEASING
- npm `latest` = 2026.10.7; GitHub page marked 2026.10.4 "Latest" on 2026-10-27. See VERIFY 4.

Real-world references
- RFC 9413, Maintaining Robust Protocols (IAB, 2023): https://www.rfc-editor.org/rfc/rfc9413.html. Claim used: tolerating faulty input entrenches errors; recommends strict, visible error handling.
- Anthropic engineering, Equipping agents for the real world with Agent Skills: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills. Claim used: only name and description load at startup; the body loads when judged relevant.
- "23 eligible skills" and "246 characters": measured on this install, not quoted.

## [VERIFY] items (6)

1. [VERIFY: the Lesson 04 link in "Where we left off" points to the Substack home page; replace with the L04 post URL.]
2. [VERIFY: run make setup/verify on macOS (bash 3.2, BSD tools) and WSL2. Written for them (portable sha256, no GNU-only flags, Python for JSON) but only run on Linux.]
3. [VERIFY: `LIVE_MODEL=<provider/model> make verify` with a real model. Not run (no API key in the sandbox); the article marks its output "verify on your machine".]
4. [VERIFY: settings ask for the latest "2.x"; OpenClaw uses date versions. npm `latest` is 2026.10.7 while GitHub shows 2026.10.4 as Latest. Confirm which you want to name.]
5. [VERIFY: config/README.md says the probe becomes the default model only when it is the only configured model. Observed `default_model=probe/skill-probe` on a sandbox with no other model; not tested with a real default configured.]
6. [VERIFY: run inside the exact L01 Docker image. Tested on a bare Ubuntu sandbox with Node 24 from npm.]

## Quality gates (run 2026-10-27)

- shellcheck -x scripts/*.sh tests/*.sh solution/*.sh: clean (shellcheck 0.11.0)
- JSON valid: config/*.json, fixtures/lint-cases.json: PASS (`make build` 6/6)
- Unit tests: 14 run, 13 pass + 1 integration test that skips without OpenClaw (passes with it)
- Mock end-to-end: verify.sh against tests/mock_openclaw.py, pass state 16/16 exit 0, fail state C3+C4 FAIL exit 1: PASS
- Live: `make bootstrap` 5/5, `make setup` 3/3 (twice, idempotent), `make verify` 16/16, `make demo` ran in ~4 s, `solution/solve.sh` 4/4
- `make clean` non-interactive: stopped probe, removed .state, did not remove the workspace skill without a yes
- Scripts executable: yes. Zip excludes .git/.env/node_modules/caches/reports/.state: yes. 28 files, under 1 MB, folder at zip root.

## Self-check

- Every command and key sourced? yes (OpenClaw-specific items above; unconfirmed items listed as VERIFY)
- verify.sh tests PROOF exactly? yes (spec, three gates, activation on real turns, negative control)
- Prose 800 words or fewer? yes, 772 (excluding code, commands, output, captions, headings and Sources)
- 2-3 sourced Field Notes? yes, 2 (RFC 9413; Anthropic Agent Skills)
- Opens from PREVIOUS and bridges to NEXT? yes (L04 allowlist; L06 secrets)
- Diagrams pass validation and the PNGs look clean? yes (fit, spacing, bounds, white first rect; PNGs inspected at 1600 px)
- Title reads "Lesson NN - TITLE"? yes, "Lesson 05 - Your first skill, written to spec"
- Article free of Portfolio checkpoint, commit command, resume line, Get the code section, GitHub link and clone commands? yes
- No banned phrases, two em dashes at most? yes, 0 em dashes
- Would a senior engineer learn something? yes: the loader silently skips or accepts off-spec skills, the per-skill prompt cost matches the documented formula to the character, and activation is separate from permission.
