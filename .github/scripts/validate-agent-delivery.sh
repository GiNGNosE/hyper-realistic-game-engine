#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

python3 - <<'PY'
import json
import os
import pathlib
import re
import subprocess
import sys

allowed_agents = {"agent1", "agent2", "agent3"}

event_path = os.environ.get("GITHUB_EVENT_PATH", "").strip()
event_name = os.environ.get("GITHUB_EVENT_NAME", "").strip()
event = {}
if event_path and pathlib.Path(event_path).exists():
    event = json.loads(pathlib.Path(event_path).read_text(encoding="utf-8"))

pr = event.get("pull_request", {}) if isinstance(event, dict) else {}
title = str(pr.get("title", "")).strip()
body = str(pr.get("body", "") or "").strip()
base_sha = str(pr.get("base", {}).get("sha", "")).strip()
head_sha = str(pr.get("head", {}).get("sha", "")).strip()
is_pr_context = isinstance(pr, dict) and bool(pr)

checks = {
    "pr_title_agent_prefix": "pass",
    "pr_body_owner_agent": "pass",
    "commit_subject_agent_prefix": "pass",
}
errors = []

title_match = re.match(r"^\[(agent1|agent2|agent3)\]\s+.+", title)
title_agent = title_match.group(1) if title_match else ""
if is_pr_context and not title_agent:
    checks["pr_title_agent_prefix"] = "fail"
    errors.append("PR title must start with [agent1], [agent2], or [agent3]")

owner_match = re.search(r"(?im)^OwnerAgent:\s*(agent1|agent2|agent3)\s*$", body)
owner_agent = owner_match.group(1) if owner_match else ""
if is_pr_context and not owner_agent:
    checks["pr_body_owner_agent"] = "fail"
    errors.append("PR body must contain 'OwnerAgent: agent1|agent2|agent3'")

if is_pr_context and owner_agent and title_agent and owner_agent != title_agent:
    checks["pr_body_owner_agent"] = "fail"
    errors.append("OwnerAgent in PR body must match PR title agent prefix")

commit_subjects = []
if is_pr_context and base_sha and head_sha:
    completed = subprocess.run(
        ["git", "log", "--format=%s", f"{base_sha}..{head_sha}"],
        capture_output=True,
        text=True,
        check=True,
    )
    commit_subjects = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if not commit_subjects:
        checks["commit_subject_agent_prefix"] = "fail"
        errors.append("No commits found in PR range")
    else:
        prefix_re = re.compile(r"^\[(agent1|agent2|agent3)\]\s+.+")
        invalid = [subject for subject in commit_subjects if not prefix_re.match(subject)]
        if invalid:
            checks["commit_subject_agent_prefix"] = "fail"
            errors.append("All commit subjects in PR must start with [agent1|agent2|agent3]")
        if owner_agent:
            mismatched = [
                subject
                for subject in commit_subjects
                if not subject.startswith(f"[{owner_agent}] ")
            ]
            if mismatched:
                checks["commit_subject_agent_prefix"] = "fail"
                errors.append("All commit subjects must match OwnerAgent prefix")
elif is_pr_context:
    checks["commit_subject_agent_prefix"] = "warn"
else:
    checks["pr_title_agent_prefix"] = "skip"
    checks["pr_body_owner_agent"] = "skip"
    checks["commit_subject_agent_prefix"] = "skip"

status = "pass" if not errors else "fail"
payload = {
    "status": status,
    "event_name": event_name,
    "owner_agent": owner_agent if owner_agent in allowed_agents else "",
    "checks": checks,
    "commit_count": len(commit_subjects),
    "commit_subjects": commit_subjects,
    "errors": errors,
}

out = pathlib.Path("artifacts/policy/agent-delivery-validation.json")
out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"Wrote {out}")

if errors:
    print("Agent delivery validation failed:")
    for err in errors:
        print(f"- {err}")
    sys.exit(1)
PY
