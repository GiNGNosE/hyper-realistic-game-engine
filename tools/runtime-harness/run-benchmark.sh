#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-benchmark.sh [--phase <phase>] [--scenario-set <id>] [--output <path>] [--backend-cmd <cmd>] [--help]

Behavior:
  - Resolves CLI flags before environment fallbacks.
  - Validates required contract inputs.
  - Executes a real benchmark backend command.
  - Validates emitted LPG payload contract before returning success.

Env fallbacks:
  POLICY_PHASE                   default: pre-phase-0
  LPG_RUNTIME_OUTPUT             default: artifacts/perf/lpg-metrics.json
  RUNTIME_BENCHMARK_BACKEND_CMD  required if --backend-cmd is not provided
EOF
}

PHASE=""
SCENARIO_SET=""
OUTPUT_PATH=""
BACKEND_CMD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      [[ $# -ge 2 ]] || { echo "Missing value for --phase" >&2; exit 2; }
      PHASE="$2"
      shift 2
      ;;
    --scenario-set)
      [[ $# -ge 2 ]] || { echo "Missing value for --scenario-set" >&2; exit 2; }
      SCENARIO_SET="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "Missing value for --output" >&2; exit 2; }
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --backend-cmd)
      [[ $# -ge 2 ]] || { echo "Missing value for --backend-cmd" >&2; exit 2; }
      BACKEND_CMD="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# CLI > env > default precedence.
PHASE="${PHASE:-${POLICY_PHASE:-pre-phase-0}}"
OUTPUT_PATH="${OUTPUT_PATH:-${LPG_RUNTIME_OUTPUT:-artifacts/perf/lpg-metrics.json}}"
BACKEND_CMD="${BACKEND_CMD:-${RUNTIME_BENCHMARK_BACKEND_CMD:-}}"

if [[ -z "${PHASE}" ]]; then
  echo "Invalid phase: value is empty" >&2
  exit 2
fi

if [[ -z "${SCENARIO_SET}" ]]; then
  echo "Missing required scenario set. Pass --scenario-set <id>." >&2
  exit 2
fi

if [[ -z "${OUTPUT_PATH}" ]]; then
  echo "Invalid output path: value is empty" >&2
  exit 2
fi

if [[ -z "${BACKEND_CMD}" ]]; then
  echo "Missing benchmark backend command. Pass --backend-cmd or set RUNTIME_BENCHMARK_BACKEND_CMD." >&2
  exit 2
fi

OUTPUT_DIR="$(dirname "${OUTPUT_PATH}")"
mkdir -p "${OUTPUT_DIR}"
if [[ ! -w "${OUTPUT_DIR}" ]]; then
  echo "Output directory is not writable: ${OUTPUT_DIR}" >&2
  exit 2
fi

echo "Executing runtime benchmark backend command..."
echo "Resolved inputs: phase=${PHASE}, scenario_set=${SCENARIO_SET}, output_path=${OUTPUT_PATH}"

rm -f "${OUTPUT_PATH}"

set +e
POLICY_PHASE="${PHASE}" \
LPG_SCENARIO_SET_ID="${SCENARIO_SET}" \
LPG_RUNTIME_OUTPUT="${OUTPUT_PATH}" \
LPG_METRICS_OUTPUT="${OUTPUT_PATH}" \
bash -lc "${BACKEND_CMD}"
backend_status=$?
set -e

if [[ ${backend_status} -ne 0 ]]; then
  echo "Runtime benchmark backend failed with exit code ${backend_status}" >&2
  exit "${backend_status}"
fi

if [[ ! -s "${OUTPUT_PATH}" ]]; then
  echo "Runtime benchmark backend did not produce non-empty output at ${OUTPUT_PATH}" >&2
  exit 1
fi

python3 - "${OUTPUT_PATH}" "${PHASE}" "${SCENARIO_SET}" <<'PY'
import json
import pathlib
import re
import sys

output_path = pathlib.Path(sys.argv[1])
expected_phase = sys.argv[2]
expected_scenario_set = sys.argv[3]
threshold_doc = pathlib.Path("docs/pipeline/validation-metrics.md")
threshold_begin = "<!-- LPG_THRESHOLDS_BEGIN -->"
threshold_end = "<!-- LPG_THRESHOLDS_END -->"


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def load_threshold_contract() -> dict:
    if not threshold_doc.exists():
        fail(f"Missing threshold source document: {threshold_doc}")
    text = threshold_doc.read_text(encoding="utf-8")
    start = text.find(threshold_begin)
    end = text.find(threshold_end)
    if start < 0 or end < 0 or end <= start:
        fail("Unable to locate LPG threshold contract markers in validation metrics document")
    body = text[start + len(threshold_begin) : end].strip()
    body = re.sub(r"^```json\s*", "", body, flags=re.MULTILINE)
    body = re.sub(r"\s*```$", "", body, flags=re.MULTILINE)
    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        fail(f"Invalid embedded LPG threshold JSON: {exc}")
    if not isinstance(payload, dict):
        fail("Embedded LPG threshold contract is not a JSON object")
    return payload


def require_non_empty_string(mapping: dict, key: str, context: str) -> None:
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(f"{context} missing non-empty string field '{key}'")


try:
    payload = json.loads(output_path.read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    fail(f"Invalid JSON at {output_path}: {exc}")

if not isinstance(payload, dict):
    fail("Runtime benchmark output must be a JSON object")

for key in ("phase", "scenario_set_id", "aggregate_metrics", "scenario_runs", "environment_fingerprint"):
    if key not in payload:
        fail(f"Runtime benchmark output missing required field '{key}'")

if payload.get("phase") != expected_phase:
    fail(f"Output phase mismatch: expected '{expected_phase}', observed '{payload.get('phase')}'")

if payload.get("scenario_set_id") != expected_scenario_set:
    fail(
        "Output scenario_set_id mismatch: "
        f"expected '{expected_scenario_set}', observed '{payload.get('scenario_set_id')}'"
    )

aggregate_metrics = payload.get("aggregate_metrics")
if not isinstance(aggregate_metrics, dict):
    fail("Runtime benchmark field 'aggregate_metrics' must be an object")

scenario_runs = payload.get("scenario_runs")
if not isinstance(scenario_runs, list) or not scenario_runs:
    fail("Runtime benchmark field 'scenario_runs' must be a non-empty array")

scenario_map = {}
for idx, run in enumerate(scenario_runs):
    if not isinstance(run, dict):
        fail(f"scenario_runs[{idx}] must be an object")
    require_non_empty_string(run, "scenario_id", f"scenario_runs[{idx}]")
    scenario_id = run["scenario_id"]
    metrics = run.get("metrics")
    if not isinstance(metrics, dict):
        fail(f"scenario_runs[{idx}] missing object field 'metrics'")
    seed = run.get("seed")
    if not isinstance(seed, (int, float)):
        fail(f"scenario_runs[{idx}] missing numeric field 'seed'")
    scenario_map[scenario_id] = run

environment = payload.get("environment_fingerprint")
if not isinstance(environment, dict):
    fail("Runtime benchmark field 'environment_fingerprint' must be an object")
for key in (
    "compiler_toolchain_id",
    "os_runtime_signature",
    "cpu_class",
    "gpu_class",
    "key_build_flags",
    "perf_profile_id",
):
    require_non_empty_string(environment, key, "environment_fingerprint")

threshold_contract = load_threshold_contract()
phases = threshold_contract.get("phases", {})
if not isinstance(phases, dict):
    fail("Threshold contract missing object field 'phases'")
phase_cfg = phases.get(expected_phase)
if not isinstance(phase_cfg, dict):
    fail(f"Threshold contract missing phase '{expected_phase}'")

phase_scenario_set = phase_cfg.get("scenario_set")
if phase_scenario_set != expected_scenario_set:
    fail(
        f"Threshold contract phase '{expected_phase}' expects scenario set "
        f"'{phase_scenario_set}', but harness invoked '{expected_scenario_set}'"
    )

scenario_sets = threshold_contract.get("scenario_sets", {})
if not isinstance(scenario_sets, dict):
    fail("Threshold contract missing object field 'scenario_sets'")
scenario_set_cfg = scenario_sets.get(expected_scenario_set, {})
if not isinstance(scenario_set_cfg, dict):
    fail(f"Threshold contract missing scenario set '{expected_scenario_set}'")
required_scenarios = scenario_set_cfg.get("scenario_ids", [])
if not isinstance(required_scenarios, list):
    fail(f"Threshold contract scenario_ids for '{expected_scenario_set}' must be an array")

for scenario_id in required_scenarios:
    if not isinstance(scenario_id, str):
        fail(f"Invalid non-string scenario id in scenario set '{expected_scenario_set}'")
    if scenario_id not in scenario_map:
        fail(f"Missing required scenario run '{scenario_id}' in output payload")

required_metrics = phase_cfg.get("required_metrics", {})
if not isinstance(required_metrics, dict):
    fail(f"Threshold contract phase '{expected_phase}' missing object field 'required_metrics'")
for metric_name, metric_cfg in required_metrics.items():
    if not isinstance(metric_cfg, dict):
        fail(f"Threshold contract metric '{metric_name}' configuration must be an object")
    scope = metric_cfg.get("scope", "aggregate")
    if scope == "scenario":
        for scenario_id in required_scenarios:
            scenario_metrics = scenario_map.get(scenario_id, {}).get("metrics", {})
            if not isinstance(scenario_metrics, dict):
                fail(f"scenario '{scenario_id}' missing metrics object")
            value = scenario_metrics.get(metric_name)
            if not isinstance(value, (int, float)):
                fail(f"scenario '{scenario_id}' missing numeric metric '{metric_name}'")
    else:
        value = aggregate_metrics.get(metric_name)
        if not isinstance(value, (int, float)):
            fail(f"aggregate_metrics missing numeric metric '{metric_name}'")

print(f"Validated LPG payload contract at {output_path}")
PY

echo "Runtime benchmark harness completed successfully."
