#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

python3 - <<'PY'
import hashlib
import json
import pathlib
import re
import sys

board_path = pathlib.Path("docs/governance/agent-task-board.md")
errors = []
checks = {
    "board_exists": "pass",
    "header_fields_present": "pass",
    "active_tasks_section_valid": "pass",
    "queued_tasks_section_valid": "pass",
    "task_schema_valid": "pass",
    "owner_agents_valid": "pass",
    "task_ids_unique": "pass",
    "status_values_valid": "pass",
    "completion_lifecycle_policy_valid": "pass",
    "board_hash_matches": "pass",
}

allowed_agents = {"agent1", "agent2", "agent3"}
allowed_status = {"assigned", "in_progress", "blocked", "done", "cancelled"}

if not board_path.exists():
    checks["board_exists"] = "fail"
    errors.append("Missing required board file: docs/governance/agent-task-board.md")
    payload = {"status": "fail", "checks": checks, "errors": errors, "tasks": []}
    out = pathlib.Path("artifacts/policy/agent-task-board-validation.json")
    out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Wrote {out}")
    sys.exit(1)

content = board_path.read_text(encoding="utf-8")


def section_body(markdown: str, heading: str) -> str:
    pattern = rf"(?ms)^## {re.escape(heading)}\s*\n(.*?)(?=^## |\Z)"
    match = re.search(pattern, markdown)
    return match.group(1).strip() if match else ""

version_match = re.search(r"(?m)^BoardVersion:\s*(\S+)\s*$", content)
hash_match = re.search(r"(?m)^BoardHash:\s*([0-9a-fA-F]+)\s*$", content)
if not version_match or not hash_match:
    checks["header_fields_present"] = "fail"
    errors.append("Board must include valid 'BoardVersion' and hex 'BoardHash' headers")

board_version = version_match.group(1) if version_match else ""
declared_hash = hash_match.group(1).lower() if hash_match else ""

normalized_for_hash = re.sub(
    r"(?m)^BoardHash:\s*[0-9a-fA-F]+\s*$",
    "BoardHash: __COMPUTED__",
    content,
)
computed_hash = hashlib.sha256(normalized_for_hash.encode("utf-8")).hexdigest()
if declared_hash and declared_hash != computed_hash:
    checks["board_hash_matches"] = "fail"
    errors.append(
        "BoardHash mismatch: run .github/scripts/update-agent-task-board.sh to refresh BoardHash"
    )

tasks = []


def extract_bullets(text_match):
    if not text_match:
        return []
    lines = text_match.group(1).strip().splitlines()
    values = []
    for line in lines:
        line = line.strip()
        if line.startswith("- "):
            values.append(line[2:].strip())
    return values


def parse_tasks_for_section(section_name: str, section_text: str):
    section_tasks = []
    task_blocks = re.split(r"(?m)^### Task\s*$", section_text)
    for block in task_blocks[1:]:
        task_id_match = re.search(r"(?m)^TaskID:\s*(\S+)\s*$", block)
        owner_match = re.search(r"(?m)^OwnerAgent:\s*(\S+)\s*$", block)
        status_match = re.search(r"(?m)^Status:\s*(\S+)\s*$", block)
        scope_match = re.search(r"(?ms)^ScopePaths:\n(.+?)(?:\n[A-Z][A-Za-z]+:|\Z)", block)
        acceptance_match = re.search(r"(?ms)^Acceptance:\n(.+?)(?:\n[A-Z][A-Za-z]+:|\Z)", block)
        evidence_match = re.search(r"(?ms)^EvidenceArtifacts:\n(.+?)(?:\n[A-Z][A-Za-z]+:|\Z)", block)

        task = {
            "section": section_name,
            "task_id": task_id_match.group(1) if task_id_match else "",
            "owner_agent": owner_match.group(1).lower() if owner_match else "",
            "status": status_match.group(1).lower() if status_match else "",
            "scope_paths": extract_bullets(scope_match),
            "acceptance": extract_bullets(acceptance_match),
            "evidence_artifacts": extract_bullets(evidence_match),
        }
        section_tasks.append(task)
    return section_tasks


active_section = section_body(content, "ActiveTasks")
queued_section = section_body(content, "QueuedTasks")

if not active_section:
    checks["active_tasks_section_valid"] = "fail"
    errors.append("Missing required section: ## ActiveTasks")
if not queued_section:
    checks["queued_tasks_section_valid"] = "fail"
    errors.append("Missing required section: ## QueuedTasks")

if active_section:
    active_tasks = parse_tasks_for_section("ActiveTasks", active_section)
    if not active_tasks:
        checks["active_tasks_section_valid"] = "fail"
        errors.append("Section ## ActiveTasks must contain at least one '### Task' block")
    tasks.extend(active_tasks)

if queued_section:
    queued_tasks = parse_tasks_for_section("QueuedTasks", queued_section)
    if not queued_tasks:
        checks["queued_tasks_section_valid"] = "fail"
        errors.append("Section ## QueuedTasks must contain at least one '### Task' block")
    tasks.extend(queued_tasks)

required_ok = True
for idx, task in enumerate(tasks):
    if not task["task_id"]:
        required_ok = False
        errors.append(f"Task block {idx} missing TaskID")
    if not task["owner_agent"]:
        required_ok = False
        errors.append(f"Task {task['task_id'] or idx} missing OwnerAgent")
    if not task["status"]:
        required_ok = False
        errors.append(f"Task {task['task_id'] or idx} missing Status")
    if not task["scope_paths"]:
        required_ok = False
        errors.append(f"Task {task['task_id'] or idx} missing ScopePaths bullet list")
    if not task["acceptance"]:
        required_ok = False
        errors.append(f"Task {task['task_id'] or idx} missing Acceptance bullet list")
    if not task["evidence_artifacts"]:
        required_ok = False
        errors.append(f"Task {task['task_id'] or idx} missing EvidenceArtifacts bullet list")

if not tasks:
    required_ok = False
    errors.append("Board must contain at least one '### Task' block")

if not required_ok:
    checks["task_schema_valid"] = "fail"

invalid_owners = [t["task_id"] for t in tasks if t["owner_agent"] not in allowed_agents]
if invalid_owners:
    checks["owner_agents_valid"] = "fail"
    errors.append("Invalid OwnerAgent for task(s): " + ", ".join(invalid_owners))

seen = set()
duplicates = set()
for task in tasks:
    tid = task["task_id"]
    if tid in seen:
        duplicates.add(tid)
    seen.add(tid)
if duplicates:
    checks["task_ids_unique"] = "fail"
    errors.append("Duplicate TaskID values found: " + ", ".join(sorted(duplicates)))

invalid_status = [t["task_id"] for t in tasks if t["status"] not in allowed_status]
if invalid_status:
    checks["status_values_valid"] = "fail"
    errors.append("Invalid Status for task(s): " + ", ".join(invalid_status))

done_tasks = [t["task_id"] for t in tasks if t["status"] == "done"]
soft_archive_pattern = re.compile(
    r"(?is)Soft-archive lifecycle applies:.*?Status:\s*done.*?orchestrator.*?after merge"
)
if done_tasks and not soft_archive_pattern.search(content):
    checks["completion_lifecycle_policy_valid"] = "fail"
    errors.append(
        "Done tasks require soft-archive dispatch note explaining orchestrator removal after merge"
    )

payload = {
    "status": "pass" if not errors else "fail",
    "board_version": board_version,
    "declared_hash": declared_hash,
    "computed_hash": computed_hash,
    "checks": checks,
    "active_task_count": len([t for t in tasks if t.get("section") == "ActiveTasks"]),
    "queued_task_count": len([t for t in tasks if t.get("section") == "QueuedTasks"]),
    "task_count": len(tasks),
    "tasks": tasks,
    "errors": errors,
}

out = pathlib.Path("artifacts/policy/agent-task-board-validation.json")
out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"Wrote {out}")

if errors:
    print("Agent task board validation failed:")
    for err in errors:
        print(f"- {err}")
    sys.exit(1)
PY
