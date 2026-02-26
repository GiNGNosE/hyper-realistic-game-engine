#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy
export REPO_ROOT
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

python3 - <<'PY'
import json
import os
import pathlib
import subprocess
import sys
import tempfile


def write_json(path: pathlib.Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


repo_root = pathlib.Path(os.environ["REPO_ROOT"]).resolve()
validator = repo_root / ".github" / "scripts" / "validate-clarification-log.sh"

scenarios = [
    {
        "id": "pull_request_missing_scope",
        "event_name": "pull_request",
        "changed_paths": [],
        "expected_exit_code": 1,
        "expected_status": "fail",
        "expected_target_scope_required": True,
        "expected_required_clarification": True,
        "expected_trigger_types": ["missing_target_scope"],
    },
    {
        "id": "push_with_scope",
        "event_name": "push",
        "changed_paths": ["docs/governance/policy-verdict.md"],
        "expected_exit_code": 0,
        "expected_status": "pass",
        "expected_target_scope_required": True,
        "expected_required_clarification": False,
        "expected_trigger_types": [],
    },
    {
        "id": "workflow_dispatch_unscoped",
        "event_name": "workflow_dispatch",
        "changed_paths": [],
        "expected_exit_code": 0,
        "expected_status": "pass",
        "expected_target_scope_required": False,
        "expected_required_clarification": False,
        "expected_trigger_types": [],
    },
    {
        "id": "schedule_unscoped",
        "event_name": "schedule",
        "changed_paths": [],
        "expected_exit_code": 0,
        "expected_status": "pass",
        "expected_target_scope_required": False,
        "expected_required_clarification": False,
        "expected_trigger_types": [],
    },
]

scenario_results = []
errors = []

for scenario in scenarios:
    with tempfile.TemporaryDirectory(prefix="clarification-guardrail-") as tmp:
        temp_root = pathlib.Path(tmp)
        policy_dir = temp_root / "artifacts" / "policy"
        policy_dir.mkdir(parents=True, exist_ok=True)

        write_json(
            policy_dir / "acceptance-criteria.json",
            {"present": True, "source": "guardrail", "generated_at": "2026-01-01T00:00:00Z"},
        )
        write_json(
            policy_dir / "rule-read-receipt.json",
            {"changed_paths": scenario["changed_paths"]},
        )

        env = os.environ.copy()
        env["GITHUB_EVENT_NAME"] = scenario["event_name"]
        proc = subprocess.run(
            ["bash", str(validator)],
            cwd=temp_root,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        validation_path = policy_dir / "clarification-validation.json"
        trigger_path = policy_dir / "ambiguity-triggers.json"
        validation = json.loads(validation_path.read_text(encoding="utf-8"))
        triggers = json.loads(trigger_path.read_text(encoding="utf-8"))
        trigger_types = [entry.get("trigger_type", "") for entry in triggers.get("triggers", [])]

        scenario_error = []
        if proc.returncode != scenario["expected_exit_code"]:
            scenario_error.append(
                f"exit_code expected {scenario['expected_exit_code']} observed {proc.returncode}"
            )
        if validation.get("status") != scenario["expected_status"]:
            scenario_error.append(
                f"status expected {scenario['expected_status']} observed {validation.get('status')}"
            )
        if bool(validation.get("target_scope_required")) != scenario["expected_target_scope_required"]:
            scenario_error.append(
                "target_scope_required mismatch: "
                f"expected {scenario['expected_target_scope_required']} "
                f"observed {validation.get('target_scope_required')}"
            )
        if bool(validation.get("required_clarification")) != scenario["expected_required_clarification"]:
            scenario_error.append(
                "required_clarification mismatch: "
                f"expected {scenario['expected_required_clarification']} "
                f"observed {validation.get('required_clarification')}"
            )
        if sorted(trigger_types) != sorted(scenario["expected_trigger_types"]):
            scenario_error.append(
                "trigger types mismatch: "
                f"expected {sorted(scenario['expected_trigger_types'])} observed {sorted(trigger_types)}"
            )

        scenario_results.append(
            {
                "id": scenario["id"],
                "event_name": scenario["event_name"],
                "expected": {
                    "exit_code": scenario["expected_exit_code"],
                    "status": scenario["expected_status"],
                    "target_scope_required": scenario["expected_target_scope_required"],
                    "required_clarification": scenario["expected_required_clarification"],
                    "trigger_types": scenario["expected_trigger_types"],
                },
                "observed": {
                    "exit_code": proc.returncode,
                    "status": validation.get("status"),
                    "target_scope_required": bool(validation.get("target_scope_required")),
                    "required_clarification": bool(validation.get("required_clarification")),
                    "trigger_types": sorted(trigger_types),
                },
                "result": "pass" if not scenario_error else "fail",
                "errors": scenario_error,
                "validator_output": proc.stdout.strip(),
            }
        )
        if scenario_error:
            errors.append(f"{scenario['id']}: " + "; ".join(scenario_error))

report = {
    "status": "pass" if not errors else "fail",
    "validator": ".github/scripts/validate-clarification-log.sh",
    "scenario_count": len(scenarios),
    "scenario_results": scenario_results,
    "errors": errors,
}

output_path = repo_root / "artifacts" / "policy" / "clarification-event-gating-guardrail.json"
write_json(output_path, report)

if errors:
    print("Clarification event-gating guardrail failed:")
    for err in errors:
        print(f"- {err}")
    sys.exit(1)

print("Clarification event-gating guardrail passed.")
PY
