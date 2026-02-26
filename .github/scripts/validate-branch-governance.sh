#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

python3 - <<'PY'
import json
import os
import pathlib
import re
import sys

event_name = os.environ.get("GITHUB_EVENT_NAME", "").strip()
event_path = os.environ.get("GITHUB_EVENT_PATH", "").strip()

errors = []
checks = {}

head_ref = os.environ.get("GITHUB_HEAD_REF", "").strip()
base_ref = os.environ.get("GITHUB_BASE_REF", "").strip()
pr_number = None

if event_path and pathlib.Path(event_path).exists():
    try:
        event = json.loads(pathlib.Path(event_path).read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"Invalid GitHub event JSON: {exc}")
        event = {}
    pr = event.get("pull_request", {}) if isinstance(event, dict) else {}
    if isinstance(pr, dict):
        head_ref = str(pr.get("head", {}).get("ref", head_ref)).strip()
        base_ref = str(pr.get("base", {}).get("ref", base_ref)).strip()
        pr_number = pr.get("number")
else:
    event = {}

is_pr_context = bool(head_ref and base_ref)
checks["pr_context_available"] = "pass" if is_pr_context else "skip"

allowed_branch_pattern = re.compile(
    r"^(feat|fix|gov|chore|exp|release|hotfix)/[a-z0-9][a-z0-9._-]{1,62}$"
)
checks["head_branch_pattern"] = "pass"
checks["base_branch_policy"] = "pass"
checks["head_not_main"] = "pass"

if is_pr_context:
    if head_ref == "main":
        checks["head_not_main"] = "fail"
        errors.append("PR head branch must not be main")

    if not allowed_branch_pattern.match(head_ref):
        checks["head_branch_pattern"] = "fail"
        errors.append(
            "Head branch violates naming policy. Allowed: "
            "feat/*, fix/*, gov/*, chore/*, exp/*, release/*, hotfix/* with lowercase slug."
        )

    allowed_base = []
    if head_ref.startswith(("feat/", "fix/", "gov/", "chore/", "exp/", "release/")):
        allowed_base = ["main"]
    elif head_ref.startswith("hotfix/"):
        allowed_base = ["main"]
        if base_ref.startswith("release/"):
            allowed_base.append(base_ref)
    else:
        allowed_base = []

    if allowed_base and base_ref not in allowed_base:
        checks["base_branch_policy"] = "fail"
        errors.append(
            f"Head branch '{head_ref}' cannot target base '{base_ref}'. "
            f"Allowed base branches: {', '.join(allowed_base)}"
        )
else:
    checks["head_branch_pattern"] = "skip"
    checks["base_branch_policy"] = "skip"
    checks["head_not_main"] = "skip"

status = "pass" if not errors else "fail"

result = {
    "status": status,
    "event_name": event_name,
    "pr_number": pr_number,
    "head_ref": head_ref,
    "base_ref": base_ref,
    "policy": {
        "head_pattern": "^(feat|fix|gov|chore|exp|release|hotfix)/[a-z0-9][a-z0-9._-]{1,62}$",
        "base_matrix": {
            "feat/*": ["main"],
            "fix/*": ["main"],
            "gov/*": ["main"],
            "chore/*": ["main"],
            "exp/*": ["main"],
            "release/*": ["main"],
            "hotfix/*": ["main", "release/*"],
        },
    },
    "checks": checks,
    "errors": errors,
}

pathlib.Path("artifacts/policy/lane-branch-governance.json").write_text(
    json.dumps(result, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

if errors:
    print("Branch governance validation failed:")
    for err in errors:
        print(f"- {err}")
    sys.exit(1)
PY
