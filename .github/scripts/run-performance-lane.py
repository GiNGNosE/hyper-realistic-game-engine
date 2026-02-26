#!/usr/bin/env python3
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
from typing import Dict, List, Tuple


ARTIFACT_DIR = pathlib.Path("artifacts/policy")
METRICS_DOC = pathlib.Path("docs/pipeline/validation-metrics.md")
BASELINE_INDEX_PATH = pathlib.Path("baselines/metrics/lpg-index.json")
DEFAULT_METRICS_INPUT = pathlib.Path(".github/fixtures/lpg/metrics-input.json")
CI_CANONICAL_METRICS_INPUT = pathlib.Path("artifacts/perf/lpg-metrics.json")
THRESHOLD_BEGIN = "<!-- LPG_THRESHOLDS_BEGIN -->"
THRESHOLD_END = "<!-- LPG_THRESHOLDS_END -->"


def write_json(name: str, payload: Dict[str, object]) -> None:
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    (ARTIFACT_DIR / name).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_json(path: pathlib.Path) -> Dict[str, object]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON at {path}: {exc}") from exc


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def git_commit_id() -> str:
    env_sha = os.environ.get("GITHUB_SHA", "").strip()
    if env_sha:
        return env_sha
    proc = subprocess.run(
        ["git", "rev-parse", "--verify", "HEAD"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    return proc.stdout.strip() if proc.returncode == 0 else ""


def parse_threshold_contract() -> Dict[str, object]:
    text = METRICS_DOC.read_text(encoding="utf-8")
    start = text.find(THRESHOLD_BEGIN)
    end = text.find(THRESHOLD_END)
    if start < 0 or end < 0 or end <= start:
        raise RuntimeError("Unable to locate LPG threshold contract markers in validation metrics document")

    body = text[start + len(THRESHOLD_BEGIN) : end].strip()
    body = re.sub(r"^```json\s*", "", body, flags=re.MULTILINE)
    body = re.sub(r"\s*```$", "", body, flags=re.MULTILINE)
    return json.loads(body)


def comparator_passes(comparator: str, observed: float, expected: float) -> bool:
    if comparator == "lte":
        return observed <= expected
    if comparator == "lt":
        return observed < expected
    if comparator == "gte":
        return observed >= expected
    if comparator == "gt":
        return observed > expected
    if comparator == "eq":
        return observed == expected
    raise ValueError(f"Unsupported comparator: {comparator}")


def validate_baseline_lineage(index_payload: Dict[str, object]) -> Tuple[str, List[str], Dict[str, Dict[str, object]]]:
    errors: List[str] = []
    baselines = index_payload.get("baselines", [])
    if not isinstance(baselines, list):
        return "fail", ["lpg-index.json must contain list field 'baselines'"], {}

    by_id: Dict[str, Dict[str, object]] = {}
    for entry in baselines:
        if isinstance(entry, dict) and isinstance(entry.get("baseline_id"), str):
            by_id[entry["baseline_id"]] = entry

    active_id = index_payload.get("active_baseline_id", "")
    if not isinstance(active_id, str) or not active_id:
        errors.append("lpg-index.json missing active_baseline_id")
    elif active_id not in by_id:
        errors.append(f"active_baseline_id '{active_id}' not found in baselines list")

    for baseline_id, entry in by_id.items():
        seen: set = set()
        current = baseline_id
        while current:
            if current in seen:
                errors.append(f"lineage cycle detected for baseline '{baseline_id}'")
                break
            seen.add(current)
            node = by_id.get(current)
            if node is None:
                errors.append(f"lineage references missing baseline '{current}'")
                break
            parent = node.get("parent_baseline_id")
            if parent is None:
                break
            if not isinstance(parent, str) or not parent:
                errors.append(f"baseline '{current}' has invalid parent_baseline_id")
                break
            current = parent

    return ("pass" if not errors else "fail"), errors, by_id


def validate_baseline_integrity(
    index_payload: Dict[str, object], baseline_map: Dict[str, Dict[str, object]]
) -> Tuple[str, List[str], Dict[str, object], Dict[str, object]]:
    errors: List[str] = []
    active_id = index_payload.get("active_baseline_id")
    active = baseline_map.get(active_id) if isinstance(active_id, str) else None
    if active is None:
        return "fail", ["Unable to resolve active baseline for integrity checks"], {}, {}

    baseline_path_value = active.get("metrics_path")
    expected_checksum = active.get("artifact_checksum_sha256")
    if not isinstance(baseline_path_value, str) or not baseline_path_value:
        errors.append("active baseline is missing metrics_path")
        return "fail", errors, active, {}

    baseline_path = pathlib.Path(baseline_path_value)
    if not baseline_path.exists():
        errors.append(f"active baseline metrics file does not exist: {baseline_path_value}")
        return "fail", errors, active, {}

    observed_checksum = sha256_file(baseline_path)
    if not isinstance(expected_checksum, str) or not expected_checksum:
        errors.append("active baseline missing artifact_checksum_sha256")
    elif observed_checksum != expected_checksum:
        errors.append(
            "active baseline checksum mismatch "
            f"(expected {expected_checksum}, observed {observed_checksum})"
        )

    baseline_payload = load_json(baseline_path)
    return ("pass" if not errors else "fail"), errors, active, baseline_payload


def index_scenarios(payload: Dict[str, object]) -> Dict[str, Dict[str, object]]:
    runs = payload.get("scenario_runs", [])
    if not isinstance(runs, list):
        return {}
    out: Dict[str, Dict[str, object]] = {}
    for run in runs:
        if not isinstance(run, dict):
            continue
        scenario_id = run.get("scenario_id")
        if isinstance(scenario_id, str):
            out[scenario_id] = run
    return out


def evaluate_thresholds(
    phase_cfg: Dict[str, object],
    scenario_ids: List[str],
    candidate_payload: Dict[str, object],
) -> Tuple[str, List[Dict[str, object]], List[str]]:
    threshold_results: List[Dict[str, object]] = []
    errors: List[str] = []
    required_metrics = phase_cfg.get("required_metrics", {})
    if not isinstance(required_metrics, dict):
        return "fail", [], ["phase configuration missing object field 'required_metrics'"]

    aggregate = candidate_payload.get("aggregate_metrics", {})
    if not isinstance(aggregate, dict):
        return "fail", [], ["candidate payload missing object field 'aggregate_metrics'"]

    scenario_map = index_scenarios(candidate_payload)
    for scenario_id in scenario_ids:
        if scenario_id not in scenario_map:
            errors.append(f"missing required scenario run: {scenario_id}")

    for metric_name, cfg in required_metrics.items():
        if not isinstance(cfg, dict):
            errors.append(f"required metric '{metric_name}' must be an object")
            continue
        comparator = cfg.get("comparator")
        expected = cfg.get("value")
        evaluation_scope = cfg.get("scope", "aggregate")
        if comparator is None or expected is None:
            errors.append(f"required metric '{metric_name}' missing comparator/value")
            continue
        if not isinstance(expected, (int, float)):
            errors.append(f"required metric '{metric_name}' value must be numeric")
            continue

        if evaluation_scope == "scenario":
            for scenario_id in scenario_ids:
                run_metrics = scenario_map.get(scenario_id, {}).get("metrics", {})
                if not isinstance(run_metrics, dict):
                    errors.append(f"scenario '{scenario_id}' missing metrics object")
                    continue
                observed = run_metrics.get(metric_name)
                if not isinstance(observed, (int, float)):
                    errors.append(f"scenario '{scenario_id}' missing numeric metric '{metric_name}'")
                    continue
                passed = comparator_passes(str(comparator), float(observed), float(expected))
                threshold_results.append(
                    {
                        "scope": "scenario",
                        "scenario_id": scenario_id,
                        "metric": metric_name,
                        "comparator": comparator,
                        "expected": expected,
                        "observed": observed,
                        "status": "pass" if passed else "fail",
                    }
                )
        else:
            observed = aggregate.get(metric_name)
            if not isinstance(observed, (int, float)):
                errors.append(f"aggregate missing numeric metric '{metric_name}'")
                continue
            passed = comparator_passes(str(comparator), float(observed), float(expected))
            threshold_results.append(
                {
                    "scope": "aggregate",
                    "metric": metric_name,
                    "comparator": comparator,
                    "expected": expected,
                    "observed": observed,
                    "status": "pass" if passed else "fail",
                }
            )

    status = "pass"
    if errors or any(item["status"] == "fail" for item in threshold_results):
        status = "fail"
    return status, threshold_results, errors


def compute_baseline_delta(
    scenario_ids: List[str], candidate_payload: Dict[str, object], baseline_payload: Dict[str, object]
) -> Dict[str, object]:
    baseline_scenarios = index_scenarios(baseline_payload)
    candidate_scenarios = index_scenarios(candidate_payload)

    deltas: List[Dict[str, object]] = []
    for scenario_id in scenario_ids:
        candidate_metrics = candidate_scenarios.get(scenario_id, {}).get("metrics", {})
        baseline_metrics = baseline_scenarios.get(scenario_id, {}).get("metrics", {})
        if not isinstance(candidate_metrics, dict) or not isinstance(baseline_metrics, dict):
            continue
        shared_metrics = sorted(set(candidate_metrics.keys()) & set(baseline_metrics.keys()))
        for metric_name in shared_metrics:
            cand = candidate_metrics.get(metric_name)
            base = baseline_metrics.get(metric_name)
            if not isinstance(cand, (int, float)) or not isinstance(base, (int, float)):
                continue
            deltas.append(
                {
                    "scenario_id": scenario_id,
                    "metric": metric_name,
                    "baseline": base,
                    "candidate": cand,
                    "delta": float(cand) - float(base),
                }
            )

    return {
        "status": "pass",
        "scenario_deltas": deltas,
        "baseline_id": baseline_payload.get("baseline_id"),
        "candidate_commit_id": git_commit_id(),
    }


def validate_environment(payload: Dict[str, object]) -> Tuple[str, List[str], Dict[str, object]]:
    required = [
        "compiler_toolchain_id",
        "os_runtime_signature",
        "cpu_class",
        "gpu_class",
        "key_build_flags",
        "perf_profile_id",
    ]
    fp = payload.get("environment_fingerprint", {})
    errors: List[str] = []
    if not isinstance(fp, dict):
        return "fail", ["candidate payload missing object field 'environment_fingerprint'"], {}
    for key in required:
        value = fp.get(key)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"environment_fingerprint missing non-empty '{key}'")
    return ("pass" if not errors else "fail"), errors, fp


def risk_signals(threshold_status: str, threshold_results: List[Dict[str, object]]) -> List[Dict[str, object]]:
    runtime_failures = [
        item
        for item in threshold_results
        if item.get("status") == "fail" and str(item.get("metric", "")).startswith("runtime_")
    ]
    if runtime_failures:
        return [
            {
                "risk_id": "R3",
                "severity": "red",
                "trigger_observed": True,
                "message": "Runtime budget threshold breach observed in current checkpoint",
                "evidence": runtime_failures,
            }
        ]
    return [
        {
            "risk_id": "R3",
            "severity": "green",
            "trigger_observed": False,
            "message": "No runtime budget breach observed in current checkpoint",
        }
    ]


def validate_candidate_schema(payload: Dict[str, object]) -> List[str]:
    errors: List[str] = []
    required_top_level = ("phase", "scenario_set_id", "aggregate_metrics", "scenario_runs", "environment_fingerprint")
    for key in required_top_level:
        if key not in payload:
            errors.append(f"candidate payload missing required field '{key}'")

    aggregate = payload.get("aggregate_metrics")
    if aggregate is not None and not isinstance(aggregate, dict):
        errors.append("candidate field 'aggregate_metrics' must be an object")

    scenario_runs = payload.get("scenario_runs")
    if scenario_runs is not None and not isinstance(scenario_runs, list):
        errors.append("candidate field 'scenario_runs' must be an array")
    if isinstance(scenario_runs, list):
        for idx, run in enumerate(scenario_runs):
            if not isinstance(run, dict):
                errors.append(f"scenario_runs[{idx}] must be an object")
                continue
            if not isinstance(run.get("scenario_id"), str) or not run.get("scenario_id"):
                errors.append(f"scenario_runs[{idx}] missing non-empty 'scenario_id'")
            metrics = run.get("metrics")
            if not isinstance(metrics, dict):
                errors.append(f"scenario_runs[{idx}] missing object field 'metrics'")

    return errors


def main() -> int:
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)

    phase = os.environ.get("POLICY_PHASE", "pre-phase-0").strip().lower()
    is_ci = os.environ.get("GITHUB_ACTIONS", "").strip().lower() == "true"
    metrics_input_env = os.environ.get("LPG_METRICS_INPUT", "").strip()
    using_env_input = bool(metrics_input_env)
    metrics_input_path = pathlib.Path(metrics_input_env or str(DEFAULT_METRICS_INPUT))

    errors: List[str] = []
    checks: Dict[str, str] = {}

    if not METRICS_DOC.exists():
        raise SystemExit(f"Missing threshold source document: {METRICS_DOC}")
    if not metrics_input_path.exists():
        if using_env_input:
            raise SystemExit(
                "Missing LPG metrics input at configured path: "
                f"{metrics_input_path}. Ensure lane-performance downloaded artifact "
                "'lpg-runtime-metrics' and set LPG_METRICS_INPUT correctly."
            )
        raise SystemExit(
            f"Missing default LPG metrics input fixture: {metrics_input_path}. "
            "Provide LPG_METRICS_INPUT to run with runtime benchmark output."
        )
    if is_ci and metrics_input_path != CI_CANONICAL_METRICS_INPUT:
        raise SystemExit(
            "CI provenance mismatch for LPG input: "
            f"expected {CI_CANONICAL_METRICS_INPUT}, observed {metrics_input_path}. "
            "CI must consume runtime harness output only."
        )
    if not BASELINE_INDEX_PATH.exists():
        raise SystemExit(f"Missing LPG baseline index: {BASELINE_INDEX_PATH}")

    threshold_contract = parse_threshold_contract()
    phases = threshold_contract.get("phases", {})
    scenario_sets = threshold_contract.get("scenario_sets", {})
    if not isinstance(phases, dict) or phase not in phases:
        raise SystemExit(f"Unsupported phase in threshold contract: {phase}")
    phase_cfg = phases[phase]
    if not isinstance(phase_cfg, dict):
        raise SystemExit(f"Invalid phase configuration format for {phase}")

    scenario_set_id = phase_cfg.get("scenario_set")
    if not isinstance(scenario_set_id, str):
        raise SystemExit(f"Phase {phase} missing scenario_set")
    scenario_cfg = scenario_sets.get(scenario_set_id, {})
    if not isinstance(scenario_cfg, dict):
        raise SystemExit(f"Scenario set {scenario_set_id} missing from threshold contract")
    scenario_ids = scenario_cfg.get("scenario_ids", [])
    if not isinstance(scenario_ids, list) or not all(isinstance(s, str) for s in scenario_ids):
        raise SystemExit(f"Scenario set {scenario_set_id} has invalid scenario_ids")

    try:
        candidate_payload = load_json(metrics_input_path)
    except RuntimeError as exc:
        raise SystemExit(str(exc)) from exc
    errors.extend(validate_candidate_schema(candidate_payload))
    if str(candidate_payload.get("phase", "")).lower() != phase:
        errors.append(f"candidate phase mismatch: expected {phase}, observed {candidate_payload.get('phase')}")
    if candidate_payload.get("scenario_set_id") != scenario_set_id:
        errors.append(
            "candidate scenario_set_id mismatch: "
            f"expected {scenario_set_id}, observed {candidate_payload.get('scenario_set_id')}"
        )

    env_status, env_errors, env_fingerprint = validate_environment(candidate_payload)
    checks["environment-fingerprint"] = env_status
    errors.extend(env_errors)
    write_json(
        "lane-performance-env.json",
        {
            "status": env_status,
            "env_class": "perf-stable-runner",
            "fingerprint": env_fingerprint,
            "errors": env_errors,
        },
    )

    index_payload = load_json(BASELINE_INDEX_PATH)
    lineage_status, lineage_errors, baseline_map = validate_baseline_lineage(index_payload)
    integrity_status, integrity_errors, active_baseline, baseline_payload = validate_baseline_integrity(
        index_payload, baseline_map
    )
    baseline_integrity_status = "pass" if lineage_status == "pass" and integrity_status == "pass" else "fail"
    baseline_integrity_errors = lineage_errors + integrity_errors
    checks["baseline-integrity"] = baseline_integrity_status
    errors.extend(baseline_integrity_errors)
    write_json(
        "baseline-integrity.json",
        {
            "status": baseline_integrity_status,
            "lineage_status": lineage_status,
            "integrity_status": integrity_status,
            "active_baseline": active_baseline,
            "errors": baseline_integrity_errors,
        },
    )

    threshold_status, threshold_results, threshold_errors = evaluate_thresholds(phase_cfg, scenario_ids, candidate_payload)
    checks["threshold-conformance"] = threshold_status
    errors.extend(threshold_errors)
    write_json(
        "lane-performance-thresholds.json",
        {
            "status": threshold_status,
            "phase": phase,
            "source_document": str(METRICS_DOC),
            "scenario_set_id": scenario_set_id,
            "results": threshold_results,
            "errors": threshold_errors,
        },
    )

    delta_payload = compute_baseline_delta(scenario_ids, candidate_payload, baseline_payload)
    checks["baseline-delta"] = "pass"
    write_json("baseline-delta.json", delta_payload)

    risk_payload = {"status": "pass", "signals": risk_signals(threshold_status, threshold_results)}
    write_json("lane-performance-risk-signals.json", risk_payload)
    checks["risk-mapping"] = "pass"

    overall_status = "pass"
    for check_status in checks.values():
        if check_status == "fail":
            overall_status = "fail"
            break
    if errors:
        overall_status = "fail"

    lane_payload = {
        "status": overall_status,
        "lane": "performance",
        "phase": phase,
        "threshold_source": str(METRICS_DOC),
        "scenario_set_id": scenario_set_id,
        "checks": checks,
        "input_metrics_path": str(metrics_input_path),
        "baseline_index_path": str(BASELINE_INDEX_PATH),
        "artifact_refs": [
            "artifacts/policy/lane-performance-env.json",
            "artifacts/policy/lane-performance-thresholds.json",
            "artifacts/policy/baseline-integrity.json",
            "artifacts/policy/baseline-delta.json",
            "artifacts/policy/lane-performance-risk-signals.json",
        ],
        "errors": errors,
    }
    write_json("lane-performance.json", lane_payload)

    if overall_status != "pass":
        print("Lane performance failed. See artifacts/policy/lane-performance.json for details.")
        return 1

    print("Lane performance passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
