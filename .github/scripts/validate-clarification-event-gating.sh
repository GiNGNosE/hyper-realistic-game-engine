#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

python3 - <<'PY'
import json
import os
import pathlib
import sys
from typing import Dict, List, Tuple

artifacts_dir = pathlib.Path("artifacts/policy")
output_path = artifacts_dir / "clarification-event-gating-guardrail.json"
scoped_events = {"pull_request", "push"}

checks: Dict[str, str] = {
    "clarification_validation_present": "pass",
    "clarification_validation_json_valid": "pass",
    "ambiguity_triggers_present": "pass",
    "ambiguity_triggers_json_valid": "pass",
    "event_scope_consistency": "pass",
}
scenario_errors: List[Dict[str, str]] = []
scenario_id = os.environ.get("MATRIX_SCENARIO_ID", "").strip()
fixture_path = os.environ.get("MATRIX_FIXTURE_PATH", "").strip()

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
output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

if status != "pass":
    print("Clarification event-gating guardrail failed:")
    for error in scenario_errors:
        print(f"- {error['code']}: {error['message']}")
    sys.exit(1)
PY
