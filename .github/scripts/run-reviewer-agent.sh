#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

python3 - <<'PY'
import json
import os
import pathlib
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
        return []
    completed = subprocess.run(
        ["git", "diff", "--name-only", base_sha, head_sha],
        capture_output=True,
        text=True,
        check=True,
    )
    return sorted([line.strip() for line in completed.stdout.splitlines() if line.strip()])


def local_changed_paths():
    paths = set()
    for cmd in (
        ["git", "diff", "--name-only"],
        ["git", "diff", "--cached", "--name-only"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ):
        completed = subprocess.run(cmd, capture_output=True, text=True, check=True)
        for line in completed.stdout.splitlines():
            line = line.strip()
            if line:
                paths.add(line)
    return sorted(paths)


event_name = os.environ.get("GITHUB_EVENT_NAME", "").strip()
event = read_event(os.environ.get("GITHUB_EVENT_PATH", "").strip())

base_sha = ""
head_sha = os.environ.get("GITHUB_SHA", "").strip()

if isinstance(event, dict) and isinstance(event.get("pull_request"), dict):
    pr = event["pull_request"]
    base_sha = str(pr.get("base", {}).get("sha", "")).strip()
    if not head_sha:
        head_sha = str(pr.get("head", {}).get("sha", "")).strip()

changed_paths = run_git_diff(base_sha, head_sha) if base_sha and head_sha else local_changed_paths()

findings = []
warnings = []
checks = {
    "changed_paths_detected": "pass" if changed_paths else "warn",
    "clarification_validator_has_matrix_guard": "pass",
    "policy_verdict_workflow_has_docs_alignment": "pass",
    "findings_owner_assignment": "pass",
}


def add_finding(
    finding_id: str,
    severity: str,
    issue: str,
    owner_agent: str,
    file_hints=None,
):
    findings.append(
        {
            "finding_id": finding_id,
            "severity": severity,
            "issue": issue,
            "owner_agent": owner_agent,
            "file_hints": file_hints or [],
            "status": "open",
        }
    )

if not changed_paths:
    warnings.append("No changed paths detected; reviewer-agent performed baseline validation only.")

clarification_validator_changed = ".github/scripts/validate-clarification-log.sh" in changed_paths
clarification_matrix_harness_changed = ".github/scripts/test-validate-clarification-log-matrix.sh" in changed_paths
if clarification_validator_changed and not clarification_matrix_harness_changed:
    checks["clarification_validator_has_matrix_guard"] = "fail"
    add_finding(
        finding_id="F001",
        severity="blocker",
        issue="validate-clarification-log.sh changed without updating test-validate-clarification-log-matrix.sh",
        owner_agent="agent1",
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

status = "fail" if findings or unassigned_findings else "pass"
risk_level = "high" if findings or unassigned_findings else ("medium" if warnings else "low")

payload = {
    "status": status,
    "event_name": event_name,
    "risk_level": risk_level,
    "checks": checks,
    "findings": findings,
    "unassigned_findings": unassigned_findings,
    "warnings": warnings,
    "changed_file_count": len(changed_paths),
    "changed_paths": changed_paths,
}

output_path = pathlib.Path("artifacts/policy/reviewer-agent-verdict.json")
output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

print(f"Wrote {output_path}")
if findings or unassigned_findings:
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
    sys.exit(1)
PY
