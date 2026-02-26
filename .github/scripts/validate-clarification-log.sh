#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

python3 - <<'PY'
import json
import pathlib
import sys

def load_json(path: pathlib.Path, default):
    if not path.exists():
        return default, False
    try:
        return json.loads(path.read_text(encoding="utf-8")), True
    except Exception as exc:
        raise SystemExit(f"Invalid JSON in {path}: {exc}")

required_rules, _ = load_json(pathlib.Path("artifacts/policy/required-rules.json"), {})
receipt, receipt_exists = load_json(pathlib.Path("artifacts/policy/rule-read-receipt.json"), {})
criteria, criteria_exists = load_json(pathlib.Path("artifacts/policy/acceptance-criteria.json"), {})
options, options_exists = load_json(pathlib.Path("artifacts/policy/implementation-options.json"), {})
conflicts, conflicts_exists = load_json(pathlib.Path("artifacts/policy/governance-conflicts.json"), {})

triggers = []
trigger_types = set()

if not criteria_exists or criteria.get("present") is not True:
    triggers.append(
        {
            "trigger_id": "T001",
            "trigger_type": "missing_acceptance_criteria",
            "detected_issue": "acceptance-criteria.json missing or present=false",
        }
    )
    trigger_types.add("missing_acceptance_criteria")

if not receipt_exists or not receipt.get("changed_paths"):
    triggers.append(
        {
            "trigger_id": "T002",
            "trigger_type": "missing_target_scope",
            "detected_issue": "changed_paths missing or empty in rule-read receipt",
        }
    )
    trigger_types.add("missing_target_scope")

if options_exists:
    candidates = options.get("candidates", [])
    selected = options.get("selected_option", "")
    if isinstance(candidates, list) and len(candidates) > 1 and not str(selected).strip():
        triggers.append(
            {
                "trigger_id": "T003",
                "trigger_type": "multiple_valid_implementations",
                "detected_issue": "multiple candidates with no selected option",
            }
        )
        trigger_types.add("multiple_valid_implementations")

if conflicts_exists and int(conflicts.get("active_conflicts", 0)) > 0:
    triggers.append(
        {
            "trigger_id": "T004",
            "trigger_type": "governance_conflict",
            "detected_issue": "governance-conflicts.json reports active conflicts",
        }
    )
    trigger_types.add("governance_conflict")

triggers_artifact = {
    "status": "triggers_detected" if triggers else "no_triggers",
    "trigger_count": len(triggers),
    "triggers": triggers,
}
pathlib.Path("artifacts/policy/ambiguity-triggers.json").write_text(
    json.dumps(triggers_artifact, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

clarification_path = pathlib.Path("artifacts/policy/clarification-log.json")
errors = []

if triggers and not clarification_path.exists():
    errors.append("Ambiguity triggers detected but clarification-log.json is missing")
    clarification = {}
else:
    clarification, clar_exists = load_json(clarification_path, {})
    if triggers and not clar_exists:
        errors.append("clarification-log.json could not be read")

if clarification_path.exists():
    for field in ("schema_version", "task_id", "commit_id", "ambiguities"):
        if field not in clarification:
            errors.append(f"clarification-log missing required field: {field}")
    ambiguities = clarification.get("ambiguities", [])
    if not isinstance(ambiguities, list):
        errors.append("clarification-log ambiguities must be an array")
        ambiguities = []

    seen_types = set()
    allowed_types = {
        "missing_acceptance_criteria",
        "multiple_valid_implementations",
        "missing_target_scope",
        "governance_conflict",
    }
    for idx, entry in enumerate(ambiguities):
        if not isinstance(entry, dict):
            errors.append(f"ambiguities[{idx}] must be an object")
            continue
        for field in (
            "ambiguity_id",
            "trigger_type",
            "detected_issue",
            "question_asked",
            "user_response",
            "resolved_decision",
            "resolved_at",
        ):
            value = entry.get(field, "")
            if not isinstance(value, str) or not value.strip():
                errors.append(f"ambiguities[{idx}].{field} must be a non-empty string")
        trigger_type = entry.get("trigger_type")
        if isinstance(trigger_type, str):
            if trigger_type not in allowed_types:
                errors.append(f"ambiguities[{idx}] contains unsupported trigger_type: {trigger_type}")
            else:
                seen_types.add(trigger_type)

    missing_types = sorted(trigger_types - seen_types)
    if missing_types:
        errors.append(
            "clarification-log does not map all detected trigger types: "
            + ", ".join(missing_types)
        )

result = {
    "status": "pass" if not errors else "fail",
    "trigger_count": len(triggers),
    "required_clarification": bool(triggers),
    "errors": errors,
}
pathlib.Path("artifacts/policy/clarification-validation.json").write_text(
    json.dumps(result, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

if errors:
    print("Clarification log validation failed:")
    for err in errors:
        print(f"- {err}")
    sys.exit(1)
PY
