#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

python3 - <<'PY'
import json
import os
import pathlib
from datetime import datetime, timezone

required_path = pathlib.Path("artifacts/policy/required-rules.json")
changed_path = pathlib.Path("artifacts/policy/changed-paths.json")
hash_path = pathlib.Path("artifacts/policy/rule-inventory-hash.txt")

if not required_path.exists():
    raise SystemExit("Missing artifacts/policy/required-rules.json")
if not changed_path.exists():
    raise SystemExit("Missing artifacts/policy/changed-paths.json")
if not hash_path.exists():
    raise SystemExit("Missing artifacts/policy/rule-inventory-hash.txt")

required = json.loads(required_path.read_text(encoding="utf-8"))
changed = json.loads(changed_path.read_text(encoding="utf-8"))
inventory_hash = hash_path.read_text(encoding="utf-8").strip()

event = {}
event_path = os.environ.get("GITHUB_EVENT_PATH", "")
if event_path and pathlib.Path(event_path).exists():
    event = json.loads(pathlib.Path(event_path).read_text(encoding="utf-8"))

pr_number = None
if isinstance(event, dict) and isinstance(event.get("pull_request"), dict):
    pr_number = event["pull_request"].get("number")

phase = required.get("phase", os.environ.get("POLICY_PHASE", "pre-phase-0"))
applicable = list(required.get("applicable_rule_ids", []))
paths = list(required.get("changed_paths", changed.get("changed_paths", [])))

task_id = f"ci-{os.environ.get('GITHUB_RUN_ID', 'local')}-{os.environ.get('GITHUB_RUN_ATTEMPT', '1')}"
commit_id = os.environ.get("GITHUB_SHA", "").strip() or "local"
generated_at = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

applied_rules = []
for rule_id in applicable:
    applied_rules.append(
        {
            "rule_id": rule_id,
            "evidence_note": (
                f"{rule_id}: must satisfy required evidence gate artifact checks "
                f"for phase {phase} with deterministic changed-path coverage."
            ),
        }
    )

receipt = {
    "schema_version": "1.0.0",
    "task_id": task_id,
    "commit_id": commit_id,
    "pr_number": pr_number,
    "phase": phase,
    "changed_paths": paths,
    "rule_inventory_hash": inventory_hash,
    "applicable_rule_ids": applicable,
    "applied_rules": applied_rules,
    "generated_at": generated_at,
}

pathlib.Path("artifacts/policy/rule-read-receipt.json").write_text(
    json.dumps(receipt, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

acceptance = {
    "present": True,
    "source": "ci-bootstrap",
    "generated_at": generated_at,
}
pathlib.Path("artifacts/policy/acceptance-criteria.json").write_text(
    json.dumps(acceptance, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
