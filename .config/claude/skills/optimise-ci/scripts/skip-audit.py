#!/usr/bin/env python3
"""Find GitHub Actions jobs that are skipped silently when an earlier job is skipped.

Usage: uv run --with pyyaml --no-project python skip-audit.py .github/workflows/*.yml

A job with no `if:` (or one that doesn't start from `always()` or `!cancelled()`) runs
only on `success()`, which is false when any ancestor, not just a direct `needs`, was
skipped. This lists each such job whose ancestors include one that can be skipped
(one with an `if:`, or a reusable-workflow call). Exits 1 if it finds any.
"""

import re
import sys

import yaml

ESCAPES = re.compile(r"\b(always|cancelled|failure)\s*\(")


def needs_of(job):
    n = job.get("needs") or []
    return [n] if isinstance(n, str) else list(n)


def audit(path):
    with open(path) as f:
        wf = yaml.safe_load(f) or {}
    jobs = wf.get("jobs") or {}
    skippable = {k for k, j in jobs.items() if "if" in j or "uses" in j}

    def ancestors(name, seen=None):
        seen = set() if seen is None else seen
        for n in needs_of(jobs.get(name, {})):
            if n not in seen:
                seen.add(n)
                ancestors(n, seen)
        return seen

    problems = []
    for name, job in jobs.items():
        cond = str(job.get("if", ""))
        if ESCAPES.search(cond):
            continue
        risky = sorted(a for a in ancestors(name) if a in skippable)
        if risky:
            problems.append((name, cond or "(none)", risky))
    return problems


def main(paths):
    found = False
    for path in paths:
        for name, cond, risky in audit(path):
            found = True
            print(f"{path}: job '{name}' (if: {cond}) is skipped if any of {risky} is skipped")
    if not found:
        print("No job is skipped silently by a skipped ancestor.")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
