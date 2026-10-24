# config/

`openclaw.gateway.json5` holds only the keys this lesson adds or changes. OpenClaw reads
JSON5 from `~/.openclaw/openclaw.json` (or `OPENCLAW_CONFIG_PATH`) and rejects unknown keys,
so merge these with `make setup` (which uses `openclaw config set`) rather than pasting blindly.

| Key | Value | Why |
| --- | --- | --- |
| `gateway.mode` | `"local"` | The Gateway refuses to start without it. |
| `gateway.port` | `18789` | Default port. `--port` and `OPENCLAW_GATEWAY_PORT` override it. |
| `gateway.bind` | `"loopback"` | Lock 1: listen on 127.0.0.1 only. |
| `gateway.auth.mode` | `"token"` | Lock 2: every caller must present the shared token. |
| `gateway.auth.rateLimit.*` | documented defaults | Failed-auth limiter. Loopback is delayed, not locked out. |

No `gateway.auth.token` key on purpose: the token comes from `OPENCLAW_GATEWAY_TOKEN`
(in `.env`, mode 600). Lesson 06 moves it into a SecretRef.

## Docker path

If your L01 sandbox is the official Docker image, the container listens on its own
interfaces (bind `lan`, which requires auth) and `docker/compose.loopback.yml` publishes
the port to `127.0.0.1` on the host only. Run verify with:

```bash
GW_MODE=docker GW_CONTAINER=<name from docker ps> \
OPENCLAW_CONFIG_PATH=<your OPENCLAW_CONFIG_DIR>/openclaw.json make verify
```

Check 01 then inspects `docker port` instead of `gateway.bind`.
