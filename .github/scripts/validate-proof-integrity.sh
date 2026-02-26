#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

python3 - <<'PY'
import json
import os
import pathlib
import sys

def load_json(path: pathlib.Path, required: bool = True):
    if not path.exists():
        if required:
            raise SystemExit(f"Missing required artifact: {path}")
        return {}
    return json.loads(path.read_text(encoding="utf-8"))

receipt = load_json(pathlib.Path("artifacts/policy/rule-read-receipt.json"))
required_rules = load_json(pathlib.Path("artifacts/policy/required-rules.json"))
changed_paths = load_json(pathlib.Path("artifacts/policy/changed-paths.json"))
triggers = load_json(pathlib.Path("artifacts/policy/ambiguity-triggers.json"), required=False)

hash_path = pathlib.Path("artifacts/policy/rule-inventory-hash.txt")
if not hash_path.exists():
    raise SystemExit("Missing required artifact: artifacts/policy/rule-inventory-hash.txt")
computed_hash = hash_path.read_text(encoding="utf-8").strip()

event_path = os.environ.get("GITHUB_EVENT_PATH", "")
event = {}
if event_path and pathlib.Path(event_path).exists():
    event = json.loads(pathlib.Path(event_path).read_text(encoding="utf-8"))

errors = []

github_sha = os.environ.get("GITHUB_SHA", "").strip()
if github_sha and receipt.get("commit_id") != github_sha:
    errors.append(
        f"commit_id mismatch: receipt={receipt.get('commit_id')} ci={github_sha}"
    )

if event.get("pull_request"):
    expected_pr = int(event["pull_request"]["number"])
    pr_value = receipt.get("pr_number")
    if pr_value != expected_pr:
        errors.append(f"pr_number mismatch: receipt={pr_value} ci={expected_pr}")

receipt_hash = str(receipt.get("rule_inventory_hash", "")).strip()
if receipt_hash != computed_hash:
    errors.append("rule_inventory_hash mismatch with CI-computed hash")

ci_paths = sorted(changed_paths.get("changed_paths", []))
receipt_paths = sorted(receipt.get("changed_paths", []))
if ci_paths != receipt_paths:
    errors.append("changed_paths mismatch between receipt and CI resolution")

phase_receipt = receipt.get("phase")
phase_resolved = required_rules.get("phase")
if phase_receipt != phase_resolved:
    errors.append(f"phase mismatch: receipt={phase_receipt} resolved={phase_resolved}")

clarification_path = pathlib.Path("artifacts/policy/clarification-log.json")
trigger_count = int(triggers.get("trigger_count", 0)) if triggers else 0
if trigger_count > 0 and not clarification_path.exists():
    errors.append("clarification-log.json missing while ambiguity triggers exist")
elif clarification_path.exists():
    clarification = load_json(clarification_path)
    if clarification.get("commit_id") != receipt.get("commit_id"):
        errors.append("clarification commit_id does not match receipt commit_id")
    if clarification.get("task_id") != receipt.get("task_id"):
        errors.append("clarification task_id does not match receipt task_id")

result = {
    "status": "pass" if not errors else "fail",
    "checks": {
        "identity_binding": "pass" if not any("mismatch" in e and "hash" not in e for e in errors) else "fail",
        "rule_hash_binding": "pass" if not any("rule_inventory_hash" in e for e in errors) else "fail",
        "changed_paths_binding": "pass" if not any("changed_paths mismatch" in e for e in errors) else "fail",
        "clarification_binding": "pass" if not any("clarification" in e for e in errors) else "fail",
    },
    "errors": errors,
}

pathlib.Path("artifacts/policy/proof-integrity-validation.json").write_text(
    json.dumps(result, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

if errors:
    print("Proof integrity validation failed:")
    for err in errors:
        print(f"- {err}")
    sys.exit(1)
PY
