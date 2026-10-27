# config/ keys (JSON has no comments, so they live here)

## exec-approvals.json (host approvals, applied with `openclaw approvals set --file`)

`approvals set` replaces the whole document. `make setup` backs up the current one to `.state/` first.
In 2026.10.x the document is stored in the `exec_approvals_config` row of `~/.openclaw/state/openclaw.sqlite`,
not in a JSON file on disk. This file is only the input.

- `version: 1` schema version.
- `defaults.security: "deny"` any agent without its own block can run nothing.
- `defaults.ask: "on-miss"` / `defaults.askFallback: "deny"` ask only on a miss; if nobody can answer, deny.
- `defaults.autoAllowSkills: false` no implicit entries from skill bin lists.
- `agents.main.security: "allowlist"` the main agent runs only allowlisted commands.
- `agents.main.ask: "on-miss"` a miss asks a human (Control UI or an approvals channel) when one is reachable.
- `agents.main.askFallback: "deny"` headless runs (cron, CLI, no approver) fail closed.
- `agents.main.allowlist[].pattern` glob against the resolved binary path, or a bare name for PATH lookups.
  Use the resolved path: on merged-/usr Linux, `/bin/ls` resolves to `/usr/bin/ls`, so `/bin/ls` never matches.
- `agents.main.allowlist[].argPattern` JavaScript regex over the arguments joined by single spaces (argv[0] excluded).
  Always anchor it with `^...$`.

Paths target the Linux sandbox from L01. On another host, find the real path with
`readlink -f "$(command -v git)"` and edit before `make setup`. `make verify` checks every path exists.

## openclaw.exec.patch.json (requested policy, applied with `openclaw config patch --file`)

- `tools.exec.mode: "ask"` is the normalized 2026.10.x form of `security: "allowlist"` + `ask: "on-miss"`.
  (Those legacy keys cannot be set together with `mode` in the same object.) It makes the requested policy
  match the host policy. OpenClaw applies the stricter of the two.
- `tools.exec.strictInlineEval: true` forces approval for inline eval forms like `python -c` and `node -e`.
- `models.providers.probe` registers the scripted probe model on `127.0.0.1:18999`. It is used only with
  `--model probe/exec-probe`, so your normal primary model is untouched. No API key: it is a loopback stub.
  `make setup` also adds `probe/*` to `agents.defaults.modelPolicy.allow` when that allowlist is present.
  Remove it after the lesson with: `echo '{"models":{"providers":{"probe":null}}}' | openclaw config patch --stdin`
