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

board_path = pathlib.Path("docs/governance/agent-task-board.md")
board_version = ""
board_tasks = {}
if board_path.exists():
    board_content = board_path.read_text(encoding="utf-8")
    version_match = re.search(r"(?m)^BoardVersion:\s*(\S+)\s*$", board_content)
    board_version = version_match.group(1) if version_match else ""
    task_blocks = re.split(r"(?m)^### Task\s*$", board_content)
    for block in task_blocks[1:]:
        task_id_match = re.search(r"(?m)^TaskID:\s*(\S+)\s*$", block)
        owner_match = re.search(r"(?m)^OwnerAgent:\s*(\S+)\s*$", block)
        status_match = re.search(r"(?m)^Status:\s*(\S+)\s*$", block)
        if task_id_match and owner_match and status_match:
            board_tasks[task_id_match.group(1)] = {
                "owner": owner_match.group(1).lower(),
                "status": status_match.group(1).lower(),
            }
else:
    board_content = ""

pr = event.get("pull_request", {}) if isinstance(event, dict) else {}
title = str(pr.get("title", "")).strip()
body = str(pr.get("body", "") or "").strip()
base_sha = str(pr.get("base", {}).get("sha", "")).strip()
head_sha = str(pr.get("head", {}).get("sha", "")).strip()
is_pr_context = isinstance(pr, dict) and bool(pr)

checks = {
    "pr_title_agent_prefix": "pass",
    "pr_body_owner_agent": "pass",
    "pr_body_task_board_version": "pass",
    "pr_body_task_id": "pass",
    "task_board_lookup_match": "pass",
    "task_status_valid": "pass",
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

task_board_version_match = re.search(r"(?im)^TaskBoardVersion:\s*(\S+)\s*$", body)
task_board_version = task_board_version_match.group(1) if task_board_version_match else ""
if is_pr_context and not task_board_version:
    checks["pr_body_task_board_version"] = "fail"
    errors.append("PR body must contain 'TaskBoardVersion: <value>'")

task_id_match = re.search(r"(?im)^TaskID:\s*(\S+)\s*$", body)
task_id = task_id_match.group(1) if task_id_match else ""
if is_pr_context and not task_id:
    checks["pr_body_task_id"] = "fail"
    errors.append("PR body must contain 'TaskID: <value>'")

if is_pr_context and owner_agent and title_agent and owner_agent != title_agent:
    checks["pr_body_owner_agent"] = "fail"
    errors.append("OwnerAgent in PR body must match PR title agent prefix")

if is_pr_context:
    if not board_content:
        checks["task_board_lookup_match"] = "fail"
        errors.append("Missing docs/governance/agent-task-board.md for delivery contract lookup")
    else:
        if not board_version:
            checks["task_board_lookup_match"] = "fail"
            errors.append("Task board missing BoardVersion header")
        if task_board_version and board_version and task_board_version != board_version:
            checks["task_board_lookup_match"] = "fail"
            errors.append(
                f"TaskBoardVersion mismatch: PR={task_board_version} board={board_version}"
            )
        if task_id:
            task_entry = board_tasks.get(task_id)
            if not task_entry:
                checks["task_board_lookup_match"] = "fail"
                errors.append(f"TaskID not found in task board: {task_id}")
            else:
                expected_owner = task_entry["owner"]
                task_status = task_entry["status"]
                if owner_agent and expected_owner != owner_agent:
                    checks["task_board_lookup_match"] = "fail"
                    errors.append(
                        f"TaskID owner mismatch: TaskID {task_id} belongs to {expected_owner}, PR declares {owner_agent}"
                    )
                if task_status == "cancelled":
                    checks["task_status_valid"] = "fail"
                    errors.append(
                        f"TaskID {task_id} is cancelled in the task board and cannot be used for PR delivery metadata"
                    )
                if task_status not in {"assigned", "in_progress", "blocked", "done", "cancelled"}:
                    checks["task_status_valid"] = "fail"
                    errors.append(
                        f"TaskID {task_id} has unsupported status '{task_status}' in task board"
                    )

commit_subjects = []
if is_pr_context and base_sha and head_sha:
    completed = subprocess.run(
        ["git", "log", "--no-merges", "--format=%s", f"{base_sha}..{head_sha}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        checks["commit_subject_agent_prefix"] = "fail"
        details = (completed.stdout or completed.stderr or "").strip() or "git log failed"
        errors.append(f"Unable to collect commit subjects for PR range {base_sha}..{head_sha}: {details}")
    else:
        commit_subjects = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if completed.returncode == 0 and not commit_subjects:
        checks["commit_subject_agent_prefix"] = "fail"
        errors.append("No commits found in PR range")
    elif completed.returncode == 0:
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
    checks["pr_body_task_board_version"] = "skip"
    checks["pr_body_task_id"] = "skip"
    checks["task_board_lookup_match"] = "skip"
    checks["task_status_valid"] = "skip"
    checks["commit_subject_agent_prefix"] = "skip"

status = "pass" if not errors else "fail"
payload = {
    "status": status,
    "event_name": event_name,
    "owner_agent": owner_agent if owner_agent in allowed_agents else "",
    "task_board_version": task_board_version,
    "task_id": task_id,
    "task_status": board_tasks.get(task_id, {}).get("status", ""),
    "board_version": board_version,
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
