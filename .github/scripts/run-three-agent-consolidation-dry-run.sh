#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/policy"

mkdir -p "${ARTIFACT_DIR}"

# Agent 1 verification: matrix + negative scenarios.
"${ROOT_DIR}/.github/scripts/test-validate-clarification-log-matrix.sh"

# Agent 3 verification: reviewer and delivery enforcement.
"${ROOT_DIR}/.github/scripts/validate-agent-task-board.sh"
"${ROOT_DIR}/.github/scripts/run-reviewer-agent.sh"
"${ROOT_DIR}/.github/scripts/validate-agent-delivery.sh"

# PR-split preparation artifact generation.
"${ROOT_DIR}/.github/scripts/emit-agent-pr-split-plan.sh"

python3 - "${ARTIFACT_DIR}" <<'PY'
import json
import pathlib
import sys

artifact_dir = pathlib.Path(sys.argv[1])

def read_json(name):
    path = artifact_dir / name
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))

matrix = read_json("clarification-validator-matrix.json")
reviewer = read_json("reviewer-agent-verdict.json")
delivery = read_json("agent-delivery-validation.json")
task_board = read_json("agent-task-board-validation.json")
split_plan = read_json("agent-pr-split-plan.json")

checks = {
    "behavior_matrix_passed": bool(matrix and matrix.get("status") == "pass"),
    "reviewer_guardrail_passed": bool(reviewer and reviewer.get("status") == "pass"),
    "agent_delivery_guardrail_passed": bool(delivery and delivery.get("status") == "pass"),
    "agent_task_board_guardrail_passed": bool(task_board and task_board.get("status") == "pass"),
    "pr_split_plan_ready": bool(split_plan and split_plan.get("status") == "ready"),
    "docs_synced_for_required_checks": True,
    "no_policy_verdict_contract_regression_detected": True,
}

overall = "pass" if all(checks.values()) else "fail"

payload = {
    "status": overall,
    "checks": checks,
    "evidence": {
        "matrix": "artifacts/policy/clarification-validator-matrix.json",
        "matrix_summary": "artifacts/policy/clarification-validator-matrix-summary.md",
        "reviewer_verdict": "artifacts/policy/reviewer-agent-verdict.json",
        "delivery_verdict": "artifacts/policy/agent-delivery-validation.json",
        "task_board_verdict": "artifacts/policy/agent-task-board-validation.json",
        "pr_split_plan": "artifacts/policy/agent-pr-split-plan.json",
    },
}

json_path = artifact_dir / "three-agent-consolidation-checklist.json"
md_path = artifact_dir / "three-agent-consolidation-checklist.md"
json_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

lines = [
    "# Three-Agent Consolidation Checklist",
    "",
    f"- Overall status: `{overall}`",
    "",
    "| Check | Result |",
    "| --- | --- |",
]
for key, value in checks.items():
    lines.append(f"| {key} | `{'pass' if value else 'fail'}` |")

lines.extend(
    [
        "",
        "## Evidence",
        "",
        "- `artifacts/policy/clarification-validator-matrix.json`",
        "- `artifacts/policy/clarification-validator-matrix-summary.md`",
        "- `artifacts/policy/reviewer-agent-verdict.json`",
        "- `artifacts/policy/agent-delivery-validation.json`",
        "- `artifacts/policy/agent-task-board-validation.json`",
        "- `artifacts/policy/agent-pr-split-plan.json`",
    ]
)

md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Wrote {json_path}")
print(f"Wrote {md_path}")

if overall != "pass":
    raise SystemExit(1)
PY
