# config/

Only what Lesson 02 adds or changes. JSON5 comments are allowed in the patch file; `approvals set` takes plain JSON, so its keys are explained here.

## l02-hardening.patch.json5

Applied by `make setup` with `openclaw config patch --stdin` (objects merge, arrays and scalars replace).

- `gateway.controlUi.allowedOrigins`: the only browser origins allowed to open the Control UI. Needed because the gateway binds `lan` inside the container (Lesson 01), so OpenClaw's own audit cannot know Docker publishes it on 127.0.0.1 only.
- `gateway.auth.rateLimit`: `maxAttempts` 10 failed auth attempts per `windowMs` 60000 (1 minute), then `lockoutMs` 300000 (5 minutes).
- `discovery.mdns.mode`: `off`. Values are `off`, `minimal` (default) and `full`; `full` adds host details such as the CLI path and SSH port to LAN broadcasts.

## exec-approvals.json

Lesson 01's exec policy, used by `make bootstrap` only when no Lesson 01 state exists (`openclaw approvals set --stdin`).

- `defaults.security`: `deny`, the agent may not run shell commands. Lesson 04 replaces this with a scoped allowlist.
- `defaults.ask`: `on-miss`, ask a human when a command is not on the allowlist.
- `defaults.askFallback`: `deny`, what happens when nobody answers.
