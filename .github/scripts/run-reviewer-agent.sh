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

ALLOWED_OWNER_AGENTS = {"agent1", "agent2", "agent3"}


def read_event(path: str):
    if not path:
        return {}
    event_file = pathlib.Path(path)
    if not event_file.exists():
        return {}
    try:
        return json.loads(event_file.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"Invalid GITHUB_EVENT_PATH JSON: {exc}")


def run_git_diff(base_sha: str, head_sha: str):
    if not base_sha or not head_sha:
        return [], []
    completed = subprocess.run(
        ["git", "diff", "--name-only", base_sha, head_sha],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        message = (completed.stdout or completed.stderr or "").strip() or "git diff failed"
        return [], [f"git diff failed for PR range {base_sha}..{head_sha}: {message}"]
    return sorted([line.strip() for line in completed.stdout.splitlines() if line.strip()]), []


def local_changed_paths():
    paths = set()
    errors = []
    for cmd in (
        ["git", "diff", "--name-only"],
        ["git", "diff", "--cached", "--name-only"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ):
        completed = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if completed.returncode != 0:
            message = (completed.stdout or completed.stderr or "").strip() or "git command failed"
            errors.append(f"{' '.join(cmd)} failed: {message}")
            continue
        for line in completed.stdout.splitlines():
            line = line.strip()
            if line:
                paths.add(line)
    return sorted(paths), errors


event_name = os.environ.get("GITHUB_EVENT_NAME", "").strip()
event = read_event(os.environ.get("GITHUB_EVENT_PATH", "").strip())

base_sha = ""
head_sha = os.environ.get("GITHUB_SHA", "").strip()

if isinstance(event, dict) and isinstance(event.get("pull_request"), dict):
    pr = event["pull_request"]
    base_sha = str(pr.get("base", {}).get("sha", "")).strip()
    if not head_sha:
        head_sha = str(pr.get("head", {}).get("sha", "")).strip()

if base_sha and head_sha:
    changed_paths, git_collection_errors = run_git_diff(base_sha, head_sha)
else:
    changed_paths, git_collection_errors = local_changed_paths()

board_path = pathlib.Path("docs/governance/agent-task-board.md")
board_tasks = {}
if board_path.exists():
    board_text = board_path.read_text(encoding="utf-8")

    def section_body(markdown: str, heading: str) -> str:
        pattern = rf"(?ms)^## {re.escape(heading)}\s*\n(.*?)(?=^## |\Z)"
        match = re.search(pattern, markdown)
        return match.group(1).strip() if match else ""

    for section_name in ("ActiveTasks", "QueuedTasks"):
        section_text = section_body(board_text, section_name)
        blocks = re.split(r"(?m)^### Task\s*$", section_text)
        for block in blocks[1:]:
            task_id_match = re.search(r"(?m)^TaskID:\s*(\S+)\s*$", block)
            owner_match = re.search(r"(?m)^OwnerAgent:\s*(\S+)\s*$", block)
            if task_id_match and owner_match:
                board_tasks[task_id_match.group(1)] = {
                    "owner_agent": owner_match.group(1).lower(),
                    "section": section_name,
                }

findings = []
warnings = []
checks = {
    "changed_paths_detected": "pass" if changed_paths else "warn",
    "git_path_collection": "pass",
    "clarification_validator_has_matrix_guard": "pass",
    "policy_verdict_workflow_has_docs_alignment": "pass",
    "findings_owner_assignment": "pass",
    "findings_task_board_mapping": "pass",
    "board_task_sections_resolved": "pass",
}


def add_finding(
    finding_id: str,
    severity: str,
    issue: str,
    owner_agent: str,
    task_id: str = "",
    file_hints=None,
):
    findings.append(
        {
            "finding_id": finding_id,
            "severity": severity,
            "issue": issue,
            "owner_agent": owner_agent,
            "task_id": task_id,
            "file_hints": file_hints or [],
            "status": "open",
        }
    )

if not changed_paths:
    warnings.append("No changed paths detected; reviewer-agent performed baseline validation only.")
if git_collection_errors:
    checks["git_path_collection"] = "warn"
    for item in git_collection_errors:
        warnings.append(item)

clarification_validator_changed = ".github/scripts/validate-clarification-log.sh" in changed_paths
clarification_matrix_harness_changed = ".github/scripts/test-validate-clarification-log-matrix.sh" in changed_paths
if clarification_validator_changed and not clarification_matrix_harness_changed:
    checks["clarification_validator_has_matrix_guard"] = "fail"
    add_finding(
        finding_id="F001",
        severity="blocker",
        issue="validate-clarification-log.sh changed without updating test-validate-clarification-log-matrix.sh",
        owner_agent="agent1",
        task_id="TB-005",
        file_hints=[
            ".github/scripts/validate-clarification-log.sh",
            ".github/scripts/test-validate-clarification-log-matrix.sh",
        ],
    )

policy_workflow_changed = ".github/workflows/policy-verdict.yml" in changed_paths
docs_changed = any(
    path in changed_paths
    for path in (
        "docs/governance/policy-verdict.md",
        "docs/governance/hybrid-proof-enforcement.md",
        "docs/governance/branch-strategy.md",
    )
)
if policy_workflow_changed and not docs_changed:
    checks["policy_verdict_workflow_has_docs_alignment"] = "fail"
    add_finding(
        finding_id="F002",
        severity="major",
        issue="policy-verdict workflow changed without companion governance doc update",
        owner_agent="agent3",
        task_id="TB-007",
        file_hints=[
            ".github/workflows/policy-verdict.yml",
            "docs/governance/policy-verdict.md",
            "docs/governance/hybrid-proof-enforcement.md",
            "docs/governance/branch-strategy.md",
        ],
    )

workflow_touched = any(path.startswith(".github/workflows/") for path in changed_paths)
script_touched = any(path.startswith(".github/scripts/") for path in changed_paths)
if workflow_touched and not script_touched:
    warnings.append(
        "Workflow files changed without script changes; confirm runtime behavior remains intended."
    )

unassigned_findings = [
    finding
    for finding in findings
    if str(finding.get("owner_agent", "")).strip().lower() not in ALLOWED_OWNER_AGENTS
]
if unassigned_findings:
    checks["findings_owner_assignment"] = "fail"

task_mismatches = []
for finding in findings:
    task_id = str(finding.get("task_id", "")).strip()
    if not task_id:
        continue
    task_entry = board_tasks.get(task_id, {})
    expected_owner = task_entry.get("owner_agent", "")
    expected_section = task_entry.get("section", "")
    if not expected_owner:
        task_mismatches.append(
            f"{finding.get('finding_id')} references unknown task_id {task_id}"
        )
        continue
    if expected_section not in {"ActiveTasks", "QueuedTasks"}:
        checks["board_task_sections_resolved"] = "fail"
        task_mismatches.append(
            f"{finding.get('finding_id')} task {task_id} has invalid board section mapping"
        )
    if expected_owner != finding.get("owner_agent"):
        task_mismatches.append(
            f"{finding.get('finding_id')} owner mismatch: task {task_id} belongs to {expected_owner}"
        )
if task_mismatches:
    checks["findings_task_board_mapping"] = "fail"

status = "fail" if findings or unassigned_findings or task_mismatches else "pass"
risk_level = (
    "high" if findings or unassigned_findings or task_mismatches else ("medium" if warnings else "low")
)

payload = {
    "status": status,
    "event_name": event_name,
    "risk_level": risk_level,
    "checks": checks,
    "findings": findings,
    "unassigned_findings": unassigned_findings,
    "task_mapping_errors": task_mismatches,
    "warnings": warnings,
    "changed_file_count": len(changed_paths),
    "changed_paths": changed_paths,
}

output_path = pathlib.Path("artifacts/policy/reviewer-agent-verdict.json")
output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

print(f"Wrote {output_path}")
if findings or unassigned_findings or task_mismatches:
    print("Reviewer-agent checks failed:")
    for finding in findings:
        print(
            "- {finding_id} [{severity}] owner={owner_agent}: {issue}".format(
                finding_id=finding.get("finding_id", ""),
                severity=finding.get("severity", ""),
                owner_agent=finding.get("owner_agent", ""),
                issue=finding.get("issue", ""),
            )
        )
    for finding in unassigned_findings:
        print(
            "- {finding_id} has invalid or missing owner_agent: {owner}".format(
                finding_id=finding.get("finding_id", ""),
                owner=finding.get("owner_agent", ""),
            )
        )
    for item in task_mismatches:
        print(f"- {item}")
    sys.exit(1)
PY
