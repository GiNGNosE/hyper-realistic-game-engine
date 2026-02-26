#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

PHASE="${POLICY_PHASE:-pre-phase-0}"
EVENT_PATH="${GITHUB_EVENT_PATH:-}"
HEAD_SHA="${GITHUB_SHA:-}"
if [[ -z "${HEAD_SHA}" ]]; then
  HEAD_SHA="$(git rev-parse --verify HEAD 2>/dev/null || true)"
fi

BASE_SHA=""
if [[ -n "${EVENT_PATH}" && -f "${EVENT_PATH}" ]]; then
  BASE_SHA="$(python3 - <<'PY'
import json
import os

path = os.environ.get("GITHUB_EVENT_PATH", "")
if not path:
    print("")
    raise SystemExit(0)

try:
    with open(path, "r", encoding="utf-8") as f:
        event = json.load(f)
except Exception:
    print("")
    raise SystemExit(0)

base = (
    event.get("pull_request", {})
    .get("base", {})
    .get("sha", "")
)
print(base or "")
PY
)"
fi

if [[ -n "${BASE_SHA}" && -n "${HEAD_SHA}" ]]; then
  git diff --name-only "${BASE_SHA}" "${HEAD_SHA}" | sed '/^$/d' > artifacts/policy/changed-paths.txt
else
  git ls-files > artifacts/policy/changed-paths.txt
fi

python3 - <<'PY'
import glob
import hashlib
import json
import os
import pathlib

phase = os.environ.get("POLICY_PHASE", "pre-phase-0").strip().lower()

phase_rules = {
    "pre-phase-0": [
        "00-core-governance-cpp",
        "05-build-toolchain-gates",
        "10-cpp-safety-subset",
        "12-program-roadmap-governance",
        "15-test-discipline",
        "30-failsafe-error-logging-contract",
        "40-determinism-envelope-and-replay",
        "45-serialization-compatibility-integrity",
        "55-operational-resilience-and-backups",
        "65-dual-objective-and-escalation",
        "70-validation-matrix-enforcement",
        "75-annual-benchmark-ladder",
    ],
    "phase-1": [
        "20-performance-critical-design",
        "35-api-abi-versioning-contract",
        "80-cross-subsystem-invariants",
    ],
    "phase-2": [
        "25-gpu-and-shader-governance",
        "50-baseline-and-promotion-policy",
    ],
    "phase-3": [
        "06-dependency-governance",
        "60-waiver-and-risk-control",
        "90-migration-and-deprecation-safety",
    ],
    "phase-4": [
        "06-dependency-governance",
        "60-waiver-and-risk-control",
        "90-migration-and-deprecation-safety",
    ],
}

if phase not in phase_rules:
    raise SystemExit(f"Unsupported POLICY_PHASE: {phase}")

active = set(phase_rules["pre-phase-0"])
if phase in ("phase-1", "phase-2", "phase-3", "phase-4"):
    active.update(phase_rules["phase-1"])
if phase in ("phase-2", "phase-3", "phase-4"):
    active.update(phase_rules["phase-2"])
if phase in ("phase-3", "phase-4"):
    active.update(phase_rules["phase-3"])

with open("artifacts/policy/changed-paths.txt", "r", encoding="utf-8") as f:
    changed_paths = [line.strip() for line in f if line.strip()]

rules_dir = pathlib.Path(".cursor/rules")
rule_files = sorted(glob.glob(str(rules_dir / "*.mdc")))
sha = hashlib.sha256()
for path in rule_files:
    with open(path, "rb") as f:
        data = f.read()
    sha.update(path.encode("utf-8"))
    sha.update(b"\0")
    sha.update(data)
    sha.update(b"\0")

inventory_hash = sha.hexdigest()

with open("artifacts/policy/rule-inventory-hash.txt", "w", encoding="utf-8") as f:
    f.write(inventory_hash + "\n")

required = {
    "phase": phase,
    "source": "docs/governance/phase-activation-matrix.md",
    "applicable_rule_ids": sorted(active),
    "changed_paths": sorted(changed_paths),
}

with open("artifacts/policy/required-rules.json", "w", encoding="utf-8") as f:
    json.dump(required, f, indent=2, sort_keys=True)
    f.write("\n")

with open("artifacts/policy/changed-paths.json", "w", encoding="utf-8") as f:
    json.dump({"changed_paths": sorted(changed_paths)}, f, indent=2, sort_keys=True)
    f.write("\n")
PY
