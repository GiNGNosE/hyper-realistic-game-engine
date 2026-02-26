#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

python3 - <<'PY'
import json
import pathlib
import re
import sys

receipt_path = pathlib.Path("artifacts/policy/rule-read-receipt.json")
required_path = pathlib.Path("artifacts/policy/required-rules.json")

errors = []

if not receipt_path.exists():
    errors.append("Missing artifacts/policy/rule-read-receipt.json")
else:
    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except Exception as exc:
        receipt = {}
        errors.append(f"Invalid JSON in rule-read-receipt.json: {exc}")

if not required_path.exists():
    errors.append("Missing artifacts/policy/required-rules.json")
    required = {}
else:
    try:
        required = json.loads(required_path.read_text(encoding="utf-8"))
    except Exception as exc:
        required = {}
        errors.append(f"Invalid JSON in required-rules.json: {exc}")

if "receipt" not in locals():
    receipt = {}

required_fields = [
    "schema_version",
    "task_id",
    "commit_id",
    "phase",
    "changed_paths",
    "rule_inventory_hash",
    "applicable_rule_ids",
    "applied_rules",
    "generated_at",
]
for field in required_fields:
    if field not in receipt:
        errors.append(f"Missing required receipt field: {field}")

if isinstance(receipt.get("changed_paths"), list):
    if not all(isinstance(v, str) and v.strip() for v in receipt["changed_paths"]):
        errors.append("changed_paths must contain non-empty strings")
else:
    if "changed_paths" in receipt:
        errors.append("changed_paths must be an array")

if isinstance(receipt.get("applicable_rule_ids"), list):
    if not all(isinstance(v, str) and v.strip() for v in receipt["applicable_rule_ids"]):
        errors.append("applicable_rule_ids must contain non-empty strings")
else:
    if "applicable_rule_ids" in receipt:
        errors.append("applicable_rule_ids must be an array")

generic_patterns = [
    r"^\s*(ok|done|n/a|na|none)\s*$",
    r"read and followed",
    r"complied with all rules",
    r"as required",
]
keyword_re = re.compile(r"\b(must|must not|required evidence|reject|gate|artifact|phase)\b", re.IGNORECASE)

applied = receipt.get("applied_rules")
seen_rule_ids = set()
if isinstance(applied, list):
    for idx, item in enumerate(applied):
        if not isinstance(item, dict):
            errors.append(f"applied_rules[{idx}] must be an object")
            continue
        rule_id = item.get("rule_id", "")
        note = item.get("evidence_note", "")
        if not isinstance(rule_id, str) or not rule_id.strip():
            errors.append(f"applied_rules[{idx}].rule_id must be a non-empty string")
        elif rule_id in seen_rule_ids:
            errors.append(f"Duplicate applied_rules.rule_id: {rule_id}")
        else:
            seen_rule_ids.add(rule_id)
        if not isinstance(note, str) or len(note.strip()) < 24:
            errors.append(f"applied_rules[{idx}].evidence_note must be >= 24 chars")
        else:
            lowered = note.strip().lower()
            if any(re.search(pat, lowered) for pat in generic_patterns):
                errors.append(f"applied_rules[{idx}].evidence_note appears generic")
            if not keyword_re.search(note):
                errors.append(
                    f"applied_rules[{idx}].evidence_note must include policy-specific keyword"
                )
else:
    if "applied_rules" in receipt:
        errors.append("applied_rules must be an array")

phase = receipt.get("phase")
resolved_phase = required.get("phase")
if phase and resolved_phase and phase != resolved_phase:
    errors.append(f"Receipt phase mismatch: receipt={phase} resolved={resolved_phase}")

result = {
    "status": "pass" if not errors else "fail",
    "checks": {
        "required_fields": "pass" if not any("Missing required receipt field" in e for e in errors) else "fail",
        "applied_rules_shape": "pass" if not any("applied_rules" in e for e in errors) else "fail",
        "evidence_specificity": "pass" if not any("evidence_note" in e for e in errors) else "fail",
        "phase_consistency": "pass" if not any("phase mismatch" in e.lower() for e in errors) else "fail",
    },
    "errors": errors,
}

pathlib.Path("artifacts/policy/rule-read-receipt-validation.json").write_text(
    json.dumps(result, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

if errors:
    print("Rule read receipt validation failed:")
    for err in errors:
        print(f"- {err}")
    sys.exit(1)
PY
