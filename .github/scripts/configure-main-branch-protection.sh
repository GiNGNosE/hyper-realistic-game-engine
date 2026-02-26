#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required."
  exit 1
fi

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "GITHUB_REPOSITORY must be set (owner/repo)."
  exit 1
fi

MANIFEST=".github/rulesets/main-protected-trunk.json"
if [[ ! -f "${MANIFEST}" ]]; then
  echo "Missing ${MANIFEST}"
  exit 1
fi

python3 - <<'PY'
import json
import os
import pathlib
import re
import subprocess
import sys

manifest = pathlib.Path(".github/rulesets/main-protected-trunk.json")
data = json.loads(manifest.read_text(encoding="utf-8"))

required_checks = data.get("required_status_checks", [])
if "policy-verdict" not in required_checks:
    raise SystemExit("Manifest must include required status check: policy-verdict")

target = data.get("target_branch", "").strip()
if target != "main":
    raise SystemExit("Manifest target_branch must be main")

if not data.get("require_pull_request", False):
    raise SystemExit("Manifest require_pull_request must be true")

strict = bool(data.get("require_up_to_date_branch", True))
allow_force_pushes = bool(data.get("allow_force_pushes", False))
allow_deletions = bool(data.get("allow_deletions", False))

checks = [{"context": check} for check in required_checks]

payload = {
    "required_status_checks": {"strict": strict, "checks": checks},
    "enforce_admins": True,
    "required_pull_request_reviews": {"required_approving_review_count": 0},
    "restrictions": None,
    "allow_force_pushes": allow_force_pushes,
    "allow_deletions": allow_deletions,
    "required_conversation_resolution": False,
    "lock_branch": False,
    "allow_fork_syncing": False,
}

owner_repo = os.environ.get("GITHUB_REPOSITORY", "")
if not re.match(r"^[^/]+/[^/]+$", owner_repo):
    raise SystemExit("GITHUB_REPOSITORY must be owner/repo")

cmd = [
    "gh",
    "api",
    f"repos/{owner_repo}/branches/main/protection",
    "--method",
    "PUT",
    "--input",
    "-",
    "-H",
    "Accept: application/vnd.github+json",
]

proc = subprocess.run(
    cmd,
    input=json.dumps(payload).encode("utf-8"),
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)

if proc.returncode != 0:
    sys.stderr.write(proc.stderr.decode("utf-8", errors="replace"))
    raise SystemExit(proc.returncode)

print("main branch protection configured from manifest")
PY
