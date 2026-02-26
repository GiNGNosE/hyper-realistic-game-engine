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
required_approvals = int(data.get("required_approving_review_count", 0))
if required_approvals < 0:
    raise SystemExit("Manifest required_approving_review_count must be >= 0")
if required_approvals > 6:
    raise SystemExit("Manifest required_approving_review_count must be <= 6")

required_conversation_resolution = bool(data.get("required_conversation_resolution", True))
allow_force_pushes = bool(data.get("allow_force_pushes", False))
allow_deletions = bool(data.get("allow_deletions", False))
allow_squash_merge = bool(data.get("allow_squash_merge", True))
allow_merge_commit = bool(data.get("allow_merge_commit", False))
allow_rebase_merge = bool(data.get("allow_rebase_merge", False))

checks = [{"context": check} for check in required_checks]

branch_protection_payload = {
    "required_status_checks": {"strict": strict, "checks": checks},
    "enforce_admins": True,
    "required_pull_request_reviews": {
        "required_approving_review_count": required_approvals
    },
    "restrictions": None,
    "allow_force_pushes": allow_force_pushes,
    "allow_deletions": allow_deletions,
    "required_conversation_resolution": required_conversation_resolution,
    "lock_branch": False,
    "allow_fork_syncing": False,
}

owner_repo = os.environ.get("GITHUB_REPOSITORY", "")
if not re.match(r"^[^/]+/[^/]+$", owner_repo):
    raise SystemExit("GITHUB_REPOSITORY must be owner/repo")

branch_cmd = [
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

branch_proc = subprocess.run(
    branch_cmd,
    input=json.dumps(branch_protection_payload).encode("utf-8"),
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if branch_proc.returncode != 0:
    sys.stderr.write("Failed to apply main branch protection.\n")
    stderr = branch_proc.stderr.decode("utf-8", errors="replace")
    stdout = branch_proc.stdout.decode("utf-8", errors="replace")
    if stderr.strip():
        sys.stderr.write(stderr + "\n")
    if stdout.strip():
        sys.stderr.write(stdout + "\n")
    raise SystemExit(branch_proc.returncode)

repo_cmd = [
    "gh",
    "api",
    f"repos/{owner_repo}",
    "--method",
    "PATCH",
    "-H",
    "Accept: application/vnd.github+json",
    "-F",
    f"allow_squash_merge={'true' if allow_squash_merge else 'false'}",
    "-F",
    f"allow_merge_commit={'true' if allow_merge_commit else 'false'}",
    "-F",
    f"allow_rebase_merge={'true' if allow_rebase_merge else 'false'}",
]
repo_proc = subprocess.run(
    repo_cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if repo_proc.returncode != 0:
    sys.stderr.write(
        "Main branch protection applied, but repository merge settings update failed.\n"
    )
    stderr = repo_proc.stderr.decode("utf-8", errors="replace")
    stdout = repo_proc.stdout.decode("utf-8", errors="replace")
    if stderr.strip():
        sys.stderr.write(stderr + "\n")
    if stdout.strip():
        sys.stderr.write(stdout + "\n")
    raise SystemExit(repo_proc.returncode)

print("main branch protection and repository merge settings configured from manifest")
PY
