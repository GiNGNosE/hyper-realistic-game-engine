#!/usr/bin/env bash
set -euo pipefail

# Local regression harness for validate-clarification-log.sh.
# Agent 3 CI wiring note: invoke this script in a dedicated validation job.
# It emits artifacts/policy/clarification-validation-matrix.json and exits non-zero on regressions.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_path="${repo_root}/artifacts/policy/clarification-validation-matrix.json"
validator_path="${repo_root}/.github/scripts/validate-clarification-log.sh"

mkdir -p "${repo_root}/artifacts/policy"

python3 - "${validator_path}" "${output_path}" <<'PY'
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

validator = pathlib.Path(sys.argv[1]).resolve()
output_path = pathlib.Path(sys.argv[2]).resolve()

scenarios = [
    {
        "id": "pr_missing_scope",
        "event_name": "pull_request",
        "include_scope": False,
        "expect_t002": True,
        "expect_target_scope_required": True,
    },
    {
        "id": "push_missing_scope",
        "event_name": "push",
        "include_scope": False,
        "expect_t002": True,
        "expect_target_scope_required": True,
    },
    {
        "id": "dispatch_missing_scope",
        "event_name": "workflow_dispatch",
        "include_scope": False,
        "expect_t002": False,
        "expect_target_scope_required": False,
    },
    {
        "id": "schedule_missing_scope",
        "event_name": "schedule",
        "include_scope": False,
        "expect_t002": False,
        "expect_target_scope_required": False,
    },
    {
        "id": "pr_with_scope",
        "event_name": "pull_request",
        "include_scope": True,
        "expect_t002": False,
        "expect_target_scope_required": True,
    },
    {
        "id": "push_with_scope",
        "event_name": "push",
        "include_scope": True,
        "expect_t002": False,
        "expect_target_scope_required": True,
    },
]


def build_fixture(case: dict, root: pathlib.Path) -> None:
    policy_dir = root / "artifacts" / "policy"
    policy_dir.mkdir(parents=True, exist_ok=True)

    (policy_dir / "acceptance-criteria.json").write_text(
        json.dumps({"present": True}, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (policy_dir / "required-rules.json").write_text(
        json.dumps({"phase": "pre-phase-0"}, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    changed_paths = ["docs/governance/clarification-log-schema.md"] if case["include_scope"] else []
    (policy_dir / "rule-read-receipt.json").write_text(
        json.dumps(
            {
                "task_id": "matrix-task",
                "commit_id": "deadbeef",
                "changed_paths": changed_paths,
                "applied_rules": [],
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    if case["expect_t002"]:
        (policy_dir / "clarification-log.json").write_text(
            json.dumps(
                {
                    "schema_version": "1.0.0",
                    "task_id": "matrix-task",
                    "commit_id": "deadbeef",
                    "ambiguities": [
                        {
                            "ambiguity_id": "A-T002",
                            "trigger_type": "missing_target_scope",
                            "detected_issue": "changed_paths missing or empty in rule-read receipt",
                            "question_asked": "Please confirm file scope for this change.",
                            "user_response": "Scope intentionally unavailable in this scenario.",
                            "resolved_decision": "Record as scoped-event clarification.",
                            "resolved_at": "2026-01-01T00:00:00Z",
                        }
                    ],
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )


def load_json(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def run_case(case: dict, matrix_root: pathlib.Path) -> dict:
    case_root = matrix_root / case["id"]
    build_fixture(case, case_root)

    run_env = dict(os.environ)
    run_env["GITHUB_EVENT_NAME"] = case["event_name"]

    proc = subprocess.run(
        [str(validator)],
        cwd=case_root,
        capture_output=True,
        text=True,
        env=run_env,
        check=False,
    )

    triggers_path = case_root / "artifacts" / "policy" / "ambiguity-triggers.json"
    validation_path = case_root / "artifacts" / "policy" / "clarification-validation.json"

    issues = []
    if not triggers_path.exists():
        issues.append("missing ambiguity-triggers.json output")
    if not validation_path.exists():
        issues.append("missing clarification-validation.json output")

    triggers = load_json(triggers_path) if triggers_path.exists() else {}
    validation = load_json(validation_path) if validation_path.exists() else {}

    trigger_types = sorted(
        t.get("trigger_type")
        for t in triggers.get("triggers", [])
        if isinstance(t, dict) and isinstance(t.get("trigger_type"), str)
    )
    has_t002 = "missing_target_scope" in trigger_types

    if has_t002 != case["expect_t002"]:
        issues.append(
            f"missing_target_scope trigger mismatch: expected={case['expect_t002']} observed={has_t002}"
        )

    event_name = validation.get("event_name")
    if event_name != case["event_name"]:
        issues.append(f"event_name mismatch: expected={case['event_name']} observed={event_name}")

    target_scope_required = validation.get("target_scope_required")
    if target_scope_required != case["expect_target_scope_required"]:
        issues.append(
            "target_scope_required mismatch: "
            f"expected={case['expect_target_scope_required']} observed={target_scope_required}"
        )

    required_clarification = validation.get("required_clarification")
    expected_required_clarification = bool(triggers.get("trigger_count", 0))
    if required_clarification != expected_required_clarification:
        issues.append(
            "required_clarification mismatch: "
            f"expected={expected_required_clarification} observed={required_clarification}"
        )

    errors = validation.get("errors")
    if not isinstance(errors, list):
        issues.append("errors field is not an array")

    missing_scope_error_present = False
    if isinstance(errors, list):
        missing_scope_error_present = any("missing_target_scope" in str(e) for e in errors)
        if case["expect_t002"] and not has_t002:
            issues.append("expected scoped-event T002 but it was absent")
        if not case["expect_t002"] and missing_scope_error_present:
            issues.append("unexpected missing_target_scope-related error in non-scoped event")

    if proc.returncode != 0:
        issues.append(f"validator exited non-zero: {proc.returncode}")

    return {
        "scenario_id": case["id"],
        "event_name": case["event_name"],
        "expect_t002": case["expect_t002"],
        "observed_t002": has_t002,
        "expect_target_scope_required": case["expect_target_scope_required"],
        "observed_target_scope_required": target_scope_required,
        "required_clarification": required_clarification,
        "validator_status": validation.get("status"),
        "validator_exit_code": proc.returncode,
        "trigger_count": triggers.get("trigger_count"),
        "trigger_types": trigger_types,
        "errors": errors if isinstance(errors, list) else [],
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
        "status": "pass" if not issues else "fail",
        "issues": issues,
    }


matrix_workspace = pathlib.Path(tempfile.mkdtemp(prefix="clarification-matrix-"))
scenario_results = []
try:
    for scenario in scenarios:
        scenario_results.append(run_case(scenario, matrix_workspace))
finally:
    shutil.rmtree(matrix_workspace)

failed = [r for r in scenario_results if r["status"] != "pass"]
summary = {
    "status": "pass" if not failed else "fail",
    "scenario_count": len(scenario_results),
    "passed_count": len(scenario_results) - len(failed),
    "failed_count": len(failed),
    "results": scenario_results,
}

output_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")

print("Clarification validation matrix summary:")
for row in scenario_results:
    print(f"- {row['scenario_id']}: {row['status']}")

if failed:
    print(f"Matrix failed in {len(failed)} scenario(s).")
    sys.exit(1)
PY
