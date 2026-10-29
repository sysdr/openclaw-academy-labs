---
name: uptime-report
description: Report how long this host has been up and its load average, using the uptime command.
metadata: { "openclaw": { "requires": { "bins": ["uptime"] }, "os": ["linux", "darwin"] } }
---

# Uptime report

Use this skill when the user asks how long the machine has been running,
when it last rebooted, or what its load average is.

1. Run `uptime` with the `exec` tool. Run nothing else.
2. Reply with exactly one line:
   `UPTIME-REPORT up=<duration> load=<1m>,<5m>,<15m>`
3. If exec is denied or fails, reply `UPTIME-REPORT error=<short reason>`.
