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
from typing import Dict, List, Tuple

scenario_id = os.environ.get("MATRIX_SCENARIO_ID", "").strip()
fixture_path = os.environ.get("MATRIX_FIXTURE_PATH", "").strip()

def write_json(path: pathlib.Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

repo_root = pathlib.Path(os.environ["REPO_ROOT"]).resolve()
scoped_events = {"pull_request", "push"}

# Matrix mode: validate artifacts produced by an explicit fixture scenario.
if scenario_id or fixture_path:
    artifacts_dir = pathlib.Path("artifacts/policy")
    output_path = artifacts_dir / "clarification-event-gating-guardrail.json"
    checks: Dict[str, str] = {
        "clarification_validation_present": "pass",
        "clarification_validation_json_valid": "pass",
        "ambiguity_triggers_present": "pass",
        "ambiguity_triggers_json_valid": "pass",
        "event_scope_consistency": "pass",
    }
    scenario_errors: List[Dict[str, str]] = []

    def add_error(code: str, artifact: str, message: str) -> None:
        record = {
            "code": code,
            "artifact": artifact,
            "message": message,
        }
        if scenario_id:
            record["scenario_id"] = scenario_id
        if fixture_path:
            record["fixture_path"] = fixture_path
        scenario_errors.append(record)

    def read_json(path: pathlib.Path, label: str) -> Tuple[Dict[str, object], bool]:
        if not path.exists():
            add_error("missing_artifact", str(path), f"{label} artifact is missing")
            checks[f"{label}_present"] = "fail"
            checks[f"{label}_json_valid"] = "skip"
            return {}, False
        checks[f"{label}_present"] = "pass"
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            add_error("invalid_json", str(path), f"{label} artifact is invalid JSON: {exc}")
            checks[f"{label}_json_valid"] = "fail"
            return {}, False
        if not isinstance(data, dict):
            add_error("invalid_shape", str(path), f"{label} artifact must be a JSON object")
            checks[f"{label}_json_valid"] = "fail"
            return {}, False
        checks[f"{label}_json_valid"] = "pass"
        return data, True

    clarification_validation, validation_ok = read_json(
        artifacts_dir / "clarification-validation.json",
        "clarification_validation",
    )
    ambiguity_triggers, triggers_ok = read_json(
        artifacts_dir / "ambiguity-triggers.json",
        "ambiguity_triggers",
    )

    event_name = str(clarification_validation.get("event_name", "")).strip()
    target_scope_required = clarification_validation.get("target_scope_required")
    trigger_types: List[str] = []
    raw_triggers = ambiguity_triggers.get("triggers", [])
    if isinstance(raw_triggers, list):
        for item in raw_triggers:
            if isinstance(item, dict):
                trigger_type = item.get("trigger_type", "")
                if isinstance(trigger_type, str) and trigger_type:
                    trigger_types.append(trigger_type)
    trigger_types = sorted(set(trigger_types))

    if validation_ok and triggers_ok:
        if not isinstance(target_scope_required, bool):
            add_error(
                "missing_field",
                str(artifacts_dir / "clarification-validation.json"),
                "target_scope_required must be a boolean",
            )
            checks["event_scope_consistency"] = "fail"
        elif target_scope_required != (event_name in scoped_events):
            add_error(
                "scope_mismatch",
                str(artifacts_dir / "clarification-validation.json"),
                (
                    "event_name and target_scope_required are inconsistent: "
                    f"event_name={event_name or 'unknown'}, target_scope_required={target_scope_required}"
                ),
            )
            checks["event_scope_consistency"] = "fail"
        if event_name and event_name not in scoped_events and "missing_target_scope" in trigger_types:
            add_error(
                "unscoped_trigger_violation",
                str(artifacts_dir / "ambiguity-triggers.json"),
                (
                    "missing_target_scope trigger must not appear for unscoped events: "
                    f"event_name={event_name}"
                ),
            )
            checks["event_scope_consistency"] = "fail"
    else:
        checks["event_scope_consistency"] = "fail"

    status = "pass" if all(value == "pass" for value in checks.values()) and not scenario_errors else "fail"
    payload = {
        "status": status,
        "scenario_id": scenario_id,
        "fixture_path": fixture_path,
        "event_name": event_name,
        "target_scope_required": target_scope_required if isinstance(target_scope_required, bool) else None,
        "checks": checks,
        "trigger_types": trigger_types,
        "scenario_error_count": len(scenario_errors),
        "scenario_errors": scenario_errors,
    }
    write_json(output_path, payload)
    if status != "pass":
        print("Clarification event-gating guardrail failed:")
        for error in scenario_errors:
            print(f"- {error['code']}: {error['message']}")
        sys.exit(1)
    raise SystemExit(0)

# Standalone mode: deterministic CI self-test harness for event gating.
validator = repo_root / ".github" / "scripts" / "validate-clarification-log.sh"
output_path = repo_root / "artifacts" / "policy" / "clarification-event-gating-guardrail.json"
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
            check=False,
        )
        validation = json.loads((policy_dir / "clarification-validation.json").read_text(encoding="utf-8"))
        triggers = json.loads((policy_dir / "ambiguity-triggers.json").read_text(encoding="utf-8"))
        trigger_types = [entry.get("trigger_type", "") for entry in triggers.get("triggers", [])]

        scenario_error = []
        if proc.returncode != scenario["expected_exit_code"]:
            scenario_error.append(f"exit_code expected {scenario['expected_exit_code']} observed {proc.returncode}")
        if validation.get("status") != scenario["expected_status"]:
            scenario_error.append(f"status expected {scenario['expected_status']} observed {validation.get('status')}")
        if bool(validation.get("target_scope_required")) != scenario["expected_target_scope_required"]:
            scenario_error.append(
                "target_scope_required mismatch: "
                f"expected {scenario['expected_target_scope_required']} observed {validation.get('target_scope_required')}"
            )
        if bool(validation.get("required_clarification")) != scenario["expected_required_clarification"]:
            scenario_error.append(
                "required_clarification mismatch: "
                f"expected {scenario['expected_required_clarification']} observed {validation.get('required_clarification')}"
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
write_json(output_path, report)
if errors:
    print("Clarification event-gating guardrail failed:")
    for err in errors:
        print(f"- {err}")
    sys.exit(1)
print("Clarification event-gating guardrail passed.")
PY
