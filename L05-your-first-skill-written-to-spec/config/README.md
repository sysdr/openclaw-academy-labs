# config/

JSON has no comments, so the keys are explained here.

## probe-provider.patch.json (added by this lesson)
Applied with `openclaw config patch --file`. Registers a local, scripted model so the
activation test runs without an API key.
- `models.providers.probe.baseUrl`: `http://127.0.0.1:18999/v1`. Loopback only; nothing leaves your machine.
- `api: "openai-completions"`: the probe speaks the OpenAI chat-completions shape.
- `models[].id: "skill-probe"`: used as `--model probe/skill-probe` on `openclaw agent`.
- No `apiKey`: the probe needs none, so no secret is stored. On OpenClaw 2026.10.7 `auth: "none"`
  is rejected by the schema; omit the field.
- Remove it later with `openclaw config set models.providers.probe null`.
- If the probe is your only configured model, OpenClaw also uses it as the default for background
  turns. The probe answers those with `PROBE idle`.

## l04-exec-approvals.json (reused from Lesson 04, applied only by `make bootstrap`)
Deny by default; the `main` agent may run `/usr/bin/uptime`, `/usr/bin/ls`, and `git` with
`status` or `log --oneline -n N`. `uptime` is the one command this lesson's skill needs.
`openclaw approvals set --file` replaces the whole document, so bootstrap backs up first and asks.

## The skill (skills/uptime-report/SKILL.md)
- `name`: lowercase slug, same as the folder.
- `description`: one line, under 160 characters. This is what the model sees before it decides.
- `metadata.openclaw.requires.bins: ["uptime"]`: not eligible on a host without `uptime`.
- `metadata.openclaw.os: ["linux", "darwin"]`: hard platform filter.
- Lesson rule (stricter than OpenClaw): metadata on one line as strict JSON. OpenClaw also accepts
  JSON5 and multi-line YAML blocks; the linter rejects them so one parser can check every skill.
