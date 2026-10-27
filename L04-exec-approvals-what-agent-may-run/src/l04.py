#!/usr/bin/env python3
"""L04 helpers used by the scripts. Standard library only.

  policy-check <approvals-get.json> <desired exec-approvals.json>
      Prints one "PASS|FAIL <check>" line per policy check.
  cases <cases.json> <canary-path>
      Prints tab-separated: name, command, expect, canary(0/1).
  classify <probe-log.jsonl> <command> [skip-lines]
      Prints allow | deny | missing for the newest record of <command>
      written after the first skip-lines lines (so old runs never count).
"""
import json
import os
import sys

DENY_MARKERS = ("exec denied", "system_run_denied", "exec policy unavailable")
INTERPRETERS = ("python", "node", "ruby", "perl", "bash", "sh", "zsh", "php", "lua", "osascript")


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def entries(doc, agent="main"):
    allow = doc.get("agents", {}).get(agent, {}).get("allowlist", [])
    return sorted((e.get("pattern", ""), e.get("argPattern", "")) for e in allow)


def policy_checks(snapshot, desired, agent="main"):
    """snapshot = output of `openclaw approvals get --json`; returns [(ok, label)]."""
    live = snapshot.get("file", snapshot)
    want = desired["agents"][agent]
    main = live.get("agents", {}).get(agent, {})
    defaults = live.get("defaults", {})
    checks = [
        (defaults.get("security") == "deny", "defaults.security is deny (agents not listed get nothing)"),
        (main.get("security") == want["security"], "agents.%s.security is %s" % (agent, want["security"])),
        (main.get("ask") == want["ask"], "agents.%s.ask is %s" % (agent, want["ask"])),
        (main.get("askFallback", defaults.get("askFallback", "deny")) == "deny",
         "askFallback is deny (fail closed when no approver answers)"),
        (main.get("autoAllowSkills") is False, "autoAllowSkills is false (no implicit entries)"),
        (entries(live, agent) == entries(desired, agent),
         "allowlist matches config exactly (%d entries)" % len(entries(desired, agent))),
        (not any(os.path.basename(p).rstrip("0123456789.") in INTERPRETERS and not a
                 for p, a in entries(live, agent)),
         "no interpreter allowlisted without argPattern"),
    ]
    scopes = snapshot.get("effectivePolicy", {}).get("scopes", [])
    scope = next((s for s in scopes if s.get("agentId") == agent), scopes[0] if scopes else {})
    effective = scope.get("security", {}).get("effective")
    checks.append((effective == "allowlist", "effective security is allowlist (got %s)" % effective))
    return checks


def classify(result_text):
    lowered = (result_text or "").lower()
    if any(marker in lowered for marker in DENY_MARKERS):
        return "deny"
    if '"status": "error"' in lowered and '"tool": "exec"' in lowered:
        return "deny"
    return "allow"


def classify_after(log_path, command, skip=0):
    """Newest probe record for this exact command, ignoring the first skip lines."""
    if not os.path.exists(log_path):
        return "missing"
    found = "missing"
    with open(log_path, encoding="utf-8") as fh:
        for number, line in enumerate(fh):
            if number < skip:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("command") == command:
                found = classify(rec.get("result", ""))
    return found


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "policy-check":
        failed = 0
        for ok, label in policy_checks(load(argv[2]), load(argv[3])):
            print("%s %s" % ("PASS" if ok else "FAIL", label))
            failed += 0 if ok else 1
        return 1 if failed else 0
    if cmd == "cases":
        for case in load(argv[2]):
            command = case["command"].replace("{canary}", argv[3])
            print("\t".join([case["name"], command, case["expect"], "1" if case.get("canary") else "0"]))
        return 0
    if cmd == "classify":
        print(classify_after(argv[2], argv[3], int(argv[4]) if len(argv) > 4 else 0))
        return 0
    print("unknown subcommand: %s" % cmd)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
