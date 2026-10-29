#!/usr/bin/env python3
"""Lint a SKILL.md against the OpenClaw skill spec (plus two stricter lesson rules).

The OpenClaw loader is permissive: it accepts an uppercase name and a name that
differs from its folder, and it skips a broken file with only a gateway log line.
This linter fails loudly instead. Standard library only.

Rules (source in VERIFICATION.md):
  R1 frontmatter between --- lines at the top of SKILL.md
  R2 only known frontmatter keys (catches typos like "descripton")
  R3 name is lowercase letters, digits and hyphens
  R4 name matches the skill's folder name
  R5 description present, one line, at most 160 characters
  R6 metadata (if any) is single-line JSON with an "openclaw" object  [lesson rule]
  R7 every requires.bins entry is on PATH                              [--check-bins]
  R8 body is non-empty and has no secret-looking strings               [lesson rule]
"""
import argparse
import json
import os
import re
import shutil
import sys

KNOWN_KEYS = {"name", "description", "metadata", "homepage", "user-invocable",
              "disable-model-invocation", "command-dispatch", "command-tool", "command-arg-mode"}
NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SECRET_RE = re.compile(r"(sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[bp]-[A-Za-z0-9-]{10,}|"
                       r"(?i:api[_-]?key|token|password)\s*[:=]\s*['\"]?[A-Za-z0-9/+_-]{12,})")
MAX_DESC = 160


def split_frontmatter(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return lines[1:i], "\n".join(lines[i + 1:])
    return None, text


def parse_keys(fm_lines):
    """Parse 'key: value' lines. Indented continuation lines are reported, not parsed."""
    keys, problems = {}, []
    for ln in fm_lines:
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        if ln[0] in " \t":
            problems.append(f"multi-line value is not allowed here: {ln.strip()[:40]!r}")
            continue
        if ":" not in ln:
            problems.append(f"not a key: value line: {ln[:40]!r}")
            continue
        k, v = ln.split(":", 1)
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
            v = v[1:-1]
        keys[k.strip()] = v
    return keys, problems


def lint(path, check_bins=False):
    """Return a list of (rule, ok, detail)."""
    results = []

    def add(rule, ok, detail):
        results.append((rule, bool(ok), detail))

    if os.path.basename(path) != "SKILL.md":
        add("R1", False, f"file must be named SKILL.md (got {os.path.basename(path)})")
        return results
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    fm, body = split_frontmatter(text)
    add("R1", fm is not None, "frontmatter between --- lines" if fm is not None else "no frontmatter block at top")
    if fm is None:
        return results
    keys, problems = parse_keys(fm)
    unknown = sorted(set(keys) - KNOWN_KEYS)
    add("R2", not unknown and not problems,
        "known keys only" if not unknown and not problems else "; ".join([f"unknown key {u!r}" for u in unknown] + problems))

    name = keys.get("name", "")
    add("R3", bool(NAME_RE.match(name)), f"name {name!r} is a lowercase slug" if NAME_RE.match(name)
        else f"name {name!r} must be lowercase letters, digits, hyphens")
    folder = os.path.basename(os.path.dirname(os.path.abspath(path)))
    add("R4", name == folder, f"name matches folder {folder!r}" if name == folder
        else f"name {name!r} differs from folder {folder!r}")

    desc = keys.get("description", "")
    ok = bool(desc) and len(desc) <= MAX_DESC
    add("R5", ok, f"description is {len(desc)} chars (max {MAX_DESC})" if desc else "description is missing")

    bins = []
    if "metadata" in keys:
        try:
            meta = json.loads(keys["metadata"])
            oc = meta.get("openclaw") if isinstance(meta, dict) else None
            good = isinstance(oc, dict)
            bins = (oc or {}).get("requires", {}).get("bins", []) if good else []
            add("R6", good, "metadata is single-line JSON with an openclaw object" if good
                else "metadata needs an \"openclaw\" object")
        except (json.JSONDecodeError, AttributeError) as exc:
            add("R6", False, f"metadata is not valid single-line JSON: {exc.msg if hasattr(exc, 'msg') else exc}")
    else:
        add("R6", True, "no metadata (skill is always eligible)")

    if check_bins:
        missing = [b for b in bins if shutil.which(b) is None]
        add("R7", not missing, "requires.bins on PATH: " + (", ".join(bins) or "none") if not missing
            else "missing on PATH: " + ", ".join(missing))

    secret = SECRET_RE.search(text)
    add("R8", body.strip() and not secret, "body present, no secret-looking strings" if body.strip() and not secret
        else ("empty body" if not body.strip() else "secret-looking string in SKILL.md"))
    return results


def main(argv=None):
    ap = argparse.ArgumentParser(description="Lint a SKILL.md against the OpenClaw skill spec.")
    ap.add_argument("skill_md", nargs="+")
    ap.add_argument("--check-bins", action="store_true", help="also require requires.bins on PATH")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    all_ok, report = True, {}
    for p in a.skill_md:
        res = lint(p, a.check_bins)
        report[p] = [{"rule": r, "ok": ok, "detail": d} for r, ok, d in res]
        all_ok &= all(ok for _, ok, _ in res)
        if not a.json:
            for r, ok, d in res:
                print(f"{r} {d:<62} {'PASS' if ok else 'FAIL'}")
    if a.json:
        print(json.dumps(report, indent=2))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
