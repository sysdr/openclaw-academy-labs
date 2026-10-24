# Assignment solution: token rotation drill

`rotate-token.sh` rotates the Gateway token and proves the old token stops working.

1. Generates a new 256-bit token and swaps it into `.env` atomically (temp file + `mv`, mode 600).
2. Restarts the Gateway: set `RESTART_CMD`, or restart it yourself when prompted.
   Environment credentials are read at process start, so a restart is required.
3. Calls `POST /tools/invoke` with the old token (expect `401`) and the new token (expect any non-auth status).

Tokens are passed to curl on stdin (`-H @-`), so they never appear in `ps` output or shell history.

Practice against the mock:

```bash
MOCK=1 make run          # terminal 1
bash solution/rotate-token.sh   # terminal 2, then Ctrl-C + MOCK=1 make run in terminal 1 when prompted
```

Expected: `3/3 PASS`.
