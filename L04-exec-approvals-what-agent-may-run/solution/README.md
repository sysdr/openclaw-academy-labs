# Assignment solution: a read-only disk check, plus four bypass attempts

What changed versus `config/exec-approvals.json`: one new entry.

```json
{ "pattern": "/usr/bin/df", "argPattern": "^-h$" }
```

Run it:

```bash
openclaw approvals set --file solution/exec-approvals.json
DESIRED=solution/exec-approvals.json CASES=solution/cases.json make verify
```

Why each new case behaves the way it does:

- `df -h` matches the binary and the anchored argPattern, so it runs.
- `df -a` hits the right binary but misses `^-h$`. Without the anchors, `-h` would also match `-ha`.
- `git -c core.pager=cat log` misses the git argPattern. `-c` lets a caller rewrite git config for one
  command, which is how an allowed git turns into an arbitrary program launcher (see GTFOBins: git).
- `sh -c '...'` is a shell wrapper. `sh` is not allowlisted, so the miss falls to askFallback=deny and
  the canary file is never created.
- `python3 -c` is inline eval. Not allowlisted here; with `tools.exec.strictInlineEval: true` it would
  need approval even if python3 were allowlisted.

Put `config/exec-approvals.json` back when you are done:
`openclaw approvals set --file config/exec-approvals.json`
