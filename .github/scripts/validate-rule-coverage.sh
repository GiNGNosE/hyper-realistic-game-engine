#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

python3 - <<'PY'
import json
import pathlib
import sys

required_path = pathlib.Path("artifacts/policy/required-rules.json")
receipt_path = pathlib.Path("artifacts/policy/rule-read-receipt.json")
errors = []

if not required_path.exists():
    errors.append("Missing artifacts/policy/required-rules.json")
    required = {}
else:
    required = json.loads(required_path.read_text(encoding="utf-8"))

if not receipt_path.exists():
    errors.append("Missing artifacts/policy/rule-read-receipt.json")
    receipt = {}
else:
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))

required_rules = set(required.get("applicable_rule_ids", []))
declared_rules = set(receipt.get("applicable_rule_ids", []))
applied_rules = {
    entry.get("rule_id")
    for entry in receipt.get("applied_rules", [])
    if isinstance(entry, dict) and isinstance(entry.get("rule_id"), str)
}

missing_from_declared = sorted(required_rules - declared_rules)
missing_from_applied = sorted(required_rules - applied_rules)
unexpected_declared = sorted(declared_rules - required_rules)

if missing_from_declared:
    errors.append(
        "Receipt applicable_rule_ids missing required rules: "
        + ", ".join(missing_from_declared)
    )
if missing_from_applied:
    errors.append(
        "Receipt applied_rules missing required rules: "
        + ", ".join(missing_from_applied)
    )
if unexpected_declared:
    errors.append(
        "Receipt declared unexpected rules for phase: "
        + ", ".join(unexpected_declared)
    )

result = {
    "status": "pass" if not errors else "fail",
    "required_count": len(required_rules),
    "declared_count": len(declared_rules),
    "applied_count": len(applied_rules),
    "missing_from_declared": missing_from_declared,
    "missing_from_applied": missing_from_applied,
    "unexpected_declared": unexpected_declared,
    "errors": errors,
}

pathlib.Path("artifacts/policy/rule-coverage-validation.json").write_text(
    json.dumps(result, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

if errors:
    print("Rule coverage validation failed:")
    for err in errors:
        print(f"- {err}")
    sys.exit(1)
PY
