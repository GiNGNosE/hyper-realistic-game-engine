#!/usr/bin/env bash
set -euo pipefail

OUTPUT_PATH="${LPG_RUNTIME_OUTPUT:-artifacts/perf/lpg-metrics.json}"
OUTPUT_DIR="$(dirname "${OUTPUT_PATH}")"
PHASE="${POLICY_PHASE:-pre-phase-0}"
IS_CI="${GITHUB_ACTIONS:-false}"
HARNESS_CMD="${RUNTIME_HARNESS_CMD:-}"
CANONICAL_OUTPUT="artifacts/perf/lpg-metrics.json"

mkdir -p "${OUTPUT_DIR}"

# CI lane must use canonical output path to keep LPG provenance stable.
if [[ "${IS_CI}" == "true" && "${OUTPUT_PATH}" != "${CANONICAL_OUTPUT}" ]]; then
  echo "Invalid LPG runtime output path in CI: '${OUTPUT_PATH}'"
  echo "Expected canonical path: '${CANONICAL_OUTPUT}'"
  exit 1
fi

# In CI, direct runtime harness command is mandatory.
if [[ "${IS_CI}" == "true" && -z "${HARNESS_CMD}" ]]; then
  echo "RUNTIME_HARNESS_CMD is required in CI and must produce ${OUTPUT_PATH}"
  exit 1
fi

if [[ -n "${HARNESS_CMD}" ]]; then
  set +e
  bash -lc "${HARNESS_CMD}"
  harness_status=$?
  set -e
  if [[ ${harness_status} -ne 0 ]]; then
    echo "Runtime harness command failed with exit code ${harness_status}"
    exit ${harness_status}
  fi
fi

if [[ -f "${OUTPUT_PATH}" ]]; then
  echo "Runtime benchmark artifact present at ${OUTPUT_PATH}"
  exit 0
fi

# Local-only bootstrap fallback keeps developer iteration easy outside CI.
if [[ "${IS_CI}" != "true" ]]; then
  python3 - <<'PY'
import json
import os
import pathlib

phase = os.environ.get("POLICY_PHASE", "pre-phase-0")
output_path = pathlib.Path(os.environ.get("LPG_RUNTIME_OUTPUT", "artifacts/perf/lpg-metrics.json"))
fixture_path = pathlib.Path(".github/fixtures/lpg/metrics-input.json")
payload = json.loads(fixture_path.read_text(encoding="utf-8"))
payload["phase"] = phase

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
fi

if [[ ! -f "${OUTPUT_PATH}" ]]; then
  if [[ "${IS_CI}" == "true" ]]; then
    echo "Runtime harness command completed but did not produce expected output: ${OUTPUT_PATH}"
    echo "Ensure RUNTIME_HARNESS_CMD writes a valid LPG metrics artifact to the canonical path."
    exit 1
  fi
  echo "Unable to generate runtime benchmark artifact at ${OUTPUT_PATH}"
  exit 1
fi

echo "Runtime benchmark artifact generated at ${OUTPUT_PATH}"
