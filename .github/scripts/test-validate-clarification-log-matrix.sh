#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
VALIDATOR_SCRIPT="${ROOT_DIR}/.github/scripts/validate-clarification-log.sh"
FIXTURE_ROOT="${ROOT_DIR}/.github/scripts/fixtures/clarification-validator"
OUTPUT_DIR="${ROOT_DIR}/artifacts/policy"

mkdir -p "${OUTPUT_DIR}"

python3 - "${VALIDATOR_SCRIPT}" "${FIXTURE_ROOT}" "${OUTPUT_DIR}" <<'PY'
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

validator_script = pathlib.Path(sys.argv[1]).resolve()
fixture_root = pathlib.Path(sys.argv[2]).resolve()
output_dir = pathlib.Path(sys.argv[3]).resolve()

matrix_output_path = output_dir / "clarification-validator-matrix.json"
summary_output_path = output_dir / "clarification-validator-matrix-summary.md"

if not validator_script.exists():
    raise SystemExit(f"Missing validator script: {validator_script}")
if not fixture_root.exists():
    raise SystemExit(f"Missing fixture root: {fixture_root}")

scenarios = [
    {
        "id": "pr_missing_scope",
        "event_name": "pull_request",
        "fixture": "scoped-target-missing",
        "expect_t002": True,
        "expect_target_scope_required": True,
        "expect_required_clarification": True,
        "expect_return_code": 1,
        "expect_error_contains": "Ambiguity triggers detected but clarification-log.json is missing",
    },
    {
        "id": "pr_scope_present",
        "event_name": "pull_request",
        "fixture": "scoped-target-present",
        "expect_t002": False,
        "expect_target_scope_required": True,
        "expect_required_clarification": False,
        "expect_return_code": 0,
    },
    {
        "id": "push_missing_scope",
        "event_name": "push",
        "fixture": "scoped-target-missing",
        "expect_t002": True,
        "expect_target_scope_required": True,
        "expect_required_clarification": True,
        "expect_return_code": 1,
        "expect_error_contains": "Ambiguity triggers detected but clarification-log.json is missing",
    },
    {
        "id": "push_scope_present",
        "event_name": "push",
        "fixture": "scoped-target-present",
        "expect_t002": False,
        "expect_target_scope_required": True,
        "expect_required_clarification": False,
        "expect_return_code": 0,
    },
    {
        "id": "workflow_dispatch_missing_scope",
        "event_name": "workflow_dispatch",
        "fixture": "scoped-target-missing",
        "expect_t002": False,
        "expect_target_scope_required": False,
        "expect_required_clarification": False,
        "expect_return_code": 0,
    },
    {
        "id": "schedule_missing_scope",
        "event_name": "schedule",
        "fixture": "scoped-target-missing",
        "expect_t002": False,
        "expect_target_scope_required": False,
        "expect_required_clarification": False,
        "expect_return_code": 0,
    },
    {
        "id": "workflow_dispatch_missing_criteria",
        "event_name": "workflow_dispatch",
        "fixture": "missing-criteria",
        "expect_t002": False,
        "expect_target_scope_required": False,
        "expect_required_clarification": True,
        "expect_return_code": 1,
        "expect_error_contains": "Ambiguity triggers detected but clarification-log.json is missing",
    },
    {
        "id": "workflow_dispatch_invalid_ambiguities_shape",
        "event_name": "workflow_dispatch",
        "fixture": "invalid-ambiguities-shape",
        "expect_t002": False,
        "expect_target_scope_required": False,
        "expect_required_clarification": True,
        "expect_return_code": 1,
        "expect_error_contains": "clarification-log ambiguities must be an array",
    },
    {
        "id": "workflow_dispatch_unsupported_trigger_type",
        "event_name": "workflow_dispatch",
        "fixture": "unsupported-trigger-type",
        "expect_t002": False,
        "expect_target_scope_required": False,
        "expect_required_clarification": True,
        "expect_return_code": 1,
        "expect_error_contains": "contains unsupported trigger_type",
    },
    {
        "id": "pull_request_invalid_receipt_json",
        "event_name": "pull_request",
        "fixture": "invalid-receipt-json",
        "expect_t002": False,
        "expect_target_scope_required": True,
        "expect_required_clarification": None,
        "expect_return_code": 1,
        "expect_error_contains": "Invalid JSON in artifacts/policy/rule-read-receipt.json",
        "expect_artifacts": False,
    },
]

results = []

for scenario in scenarios:
    fixture_dir = fixture_root / scenario["fixture"]
    if not fixture_dir.exists():
        raise SystemExit(f"Missing fixture directory: {fixture_dir}")

    with tempfile.TemporaryDirectory(prefix="clarification-matrix-") as tmp:
        workspace = pathlib.Path(tmp)
        shutil.copytree(fixture_dir, workspace, dirs_exist_ok=True)

        env = os.environ.copy()
        env["GITHUB_EVENT_NAME"] = scenario["event_name"]

        run = subprocess.run(
            [str(validator_script)],
            cwd=workspace,
            env=env,
            capture_output=True,
            text=True,
        )

        triggers_path = workspace / "artifacts/policy/ambiguity-triggers.json"
        validation_path = workspace / "artifacts/policy/clarification-validation.json"
        expect_artifacts = scenario.get("expect_artifacts", True)
        artifacts_exist = triggers_path.exists() and validation_path.exists()

        if not artifacts_exist:
            assertions = [
                {
                    "name": "artifacts_exist",
                    "expected": expect_artifacts,
                    "actual": artifacts_exist,
                    "pass": artifacts_exist == expect_artifacts,
                },
                {
                    "name": "return_code",
                    "expected": scenario["expect_return_code"],
                    "actual": run.returncode,
                    "pass": run.returncode == scenario["expect_return_code"],
                },
            ]
            if "expect_error_contains" in scenario:
                combined_output = (run.stdout or "") + "\n" + (run.stderr or "")
                assertions.append(
                    {
                        "name": "error_contains_expected_text",
                        "expected": scenario["expect_error_contains"],
                        "actual": scenario["expect_error_contains"] in combined_output,
                        "pass": scenario["expect_error_contains"] in combined_output,
                    }
                )
            results.append(
                {
                    "scenario": scenario["id"],
                    "event_name": scenario["event_name"],
                    "status": "pass" if all(item["pass"] for item in assertions) else "fail",
                    "return_code": run.returncode,
                    "assertions": assertions,
                    "stdout": run.stdout,
                    "stderr": run.stderr,
                }
            )
            continue

        triggers = json.loads(triggers_path.read_text(encoding="utf-8"))
        validation = json.loads(validation_path.read_text(encoding="utf-8"))
        t002_present = any(
            trigger.get("trigger_type") == "missing_target_scope"
            for trigger in triggers.get("triggers", [])
            if isinstance(trigger, dict)
        )

        assertions = []
        assertions.append(
            {
                "name": "t002_event_gating",
                "expected": scenario["expect_t002"],
                "actual": t002_present,
                "pass": t002_present == scenario["expect_t002"],
            }
        )

        has_contract_keys = all(
            key in validation
            for key in ("event_name", "target_scope_required", "required_clarification", "errors")
        )
        assertions.append(
            {
                "name": "clarification_validation_contract_keys",
                "expected": True,
                "actual": has_contract_keys,
                "pass": has_contract_keys,
            }
        )

        assertions.append(
            {
                "name": "event_name_echoed",
                "expected": scenario["event_name"],
                "actual": validation.get("event_name"),
                "pass": validation.get("event_name") == scenario["event_name"],
            }
        )
        assertions.append(
            {
                "name": "target_scope_required_flag",
                "expected": scenario["expect_target_scope_required"],
                "actual": validation.get("target_scope_required"),
                "pass": validation.get("target_scope_required")
                == scenario["expect_target_scope_required"],
            }
        )
        assertions.append(
            {
                "name": "required_clarification_matches_t002",
                "expected": scenario["expect_required_clarification"],
                "actual": validation.get("required_clarification"),
                "pass": validation.get("required_clarification")
                == scenario["expect_required_clarification"],
            }
        )
        assertions.append(
            {
                "name": "return_code",
                "expected": scenario["expect_return_code"],
                "actual": run.returncode,
                "pass": run.returncode == scenario["expect_return_code"],
            }
        )
        assertions.append(
            {
                "name": "errors_is_array",
                "expected": "list",
                "actual": type(validation.get("errors")).__name__,
                "pass": isinstance(validation.get("errors"), list),
            }
        )
        if "expect_error_contains" in scenario:
            assertions.append(
                {
                    "name": "error_contains_expected_text",
                    "expected": scenario["expect_error_contains"],
                    "actual": any(
                        scenario["expect_error_contains"] in error
                        for error in validation.get("errors", [])
                    ),
                    "pass": any(
                        scenario["expect_error_contains"] in error
                        for error in validation.get("errors", [])
                    ),
                }
            )

        scenario_pass = all(assertion["pass"] for assertion in assertions)
        results.append(
            {
                "scenario": scenario["id"],
                "event_name": scenario["event_name"],
                "status": "pass" if scenario_pass else "fail",
                "return_code": run.returncode,
                "assertions": assertions,
                "trigger_count": triggers.get("trigger_count"),
                "missing_target_scope_detected": t002_present,
                "required_clarification": validation.get("required_clarification"),
                "validation_status": validation.get("status"),
                "errors": validation.get("errors"),
                "stdout": run.stdout,
                "stderr": run.stderr,
            }
        )

matrix_payload = {
    "status": "pass" if all(item["status"] == "pass" for item in results) else "fail",
    "scenario_count": len(results),
    "scenarios": results,
}

matrix_output_path.write_text(
    json.dumps(matrix_payload, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

summary_lines = [
    "# Clarification Validator Event Matrix",
    "",
    f"- Overall status: `{matrix_payload['status']}`",
    f"- Scenario count: `{matrix_payload['scenario_count']}`",
    "",
    "| Scenario | Event | Expected T002 | Actual T002 | Expected RC | Actual RC | Status |",
    "| --- | --- | --- | --- | --- | --- | --- |",
]

for scenario in results:
    t002_assertion = next(
        (assertion for assertion in scenario["assertions"] if assertion["name"] == "t002_event_gating"),
        None,
    )
    rc_assertion = next(
        (assertion for assertion in scenario["assertions"] if assertion["name"] == "return_code"),
        None,
    )
    expected_t002 = t002_assertion["expected"] if t002_assertion else "n/a"
    actual_t002 = t002_assertion["actual"] if t002_assertion else "n/a"
    expected_rc = rc_assertion["expected"] if rc_assertion else "n/a"
    actual_rc = rc_assertion["actual"] if rc_assertion else "n/a"
    summary_lines.append(
        "| {scenario_id} | {event_name} | `{expected}` | `{actual}` | `{expected_rc}` | `{actual_rc}` | `{status}` |".format(
            scenario_id=scenario["scenario"],
            event_name=scenario["event_name"],
            expected=str(expected_t002).lower(),
            actual=str(actual_t002).lower(),
            expected_rc=expected_rc,
            actual_rc=actual_rc,
            status=scenario["status"],
        )
    )

summary_output_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

if matrix_payload["status"] != "pass":
    print(json.dumps(matrix_payload, indent=2))
    raise SystemExit(1)

print(f"Wrote {matrix_output_path}")
print(f"Wrote {summary_output_path}")
PY
