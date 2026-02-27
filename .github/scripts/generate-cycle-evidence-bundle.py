#!/usr/bin/env python3
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
from typing import Dict, List, Optional, Tuple


ARTIFACTS_POLICY_DIR = pathlib.Path("artifacts/policy")
ARTIFACTS_PERF_DIR = pathlib.Path("artifacts/perf")
BUNDLE_DIR = pathlib.Path("artifacts/cycle-evidence")

LANE_PERFORMANCE_PATH = ARTIFACTS_POLICY_DIR / "lane-performance.json"
THRESHOLDS_PATH = ARTIFACTS_POLICY_DIR / "lane-performance-thresholds.json"
BASELINE_DELTA_PATH = ARTIFACTS_POLICY_DIR / "baseline-delta.json"
BASELINE_INTEGRITY_PATH = ARTIFACTS_POLICY_DIR / "baseline-integrity.json"
RISK_SIGNALS_PATH = ARTIFACTS_POLICY_DIR / "lane-performance-risk-signals.json"
ENV_FINGERPRINT_PATH = ARTIFACTS_POLICY_DIR / "lane-performance-env.json"
RUNTIME_METRICS_PATH = ARTIFACTS_PERF_DIR / "lpg-metrics.json"

ADR_INDEX_PATH = pathlib.Path("docs/governance/adr-index.md")

SUMMARY_JSON_PATH = BUNDLE_DIR / "cycle-evidence-summary.json"
SUMMARY_MD_PATH = BUNDLE_DIR / "cycle-evidence-summary.md"
INDEX_JSON_PATH = BUNDLE_DIR / "evidence-index.json"

REQUIRED_INPUTS = {
    "lane_performance": LANE_PERFORMANCE_PATH,
    "thresholds": THRESHOLDS_PATH,
    "baseline_delta": BASELINE_DELTA_PATH,
    "baseline_integrity": BASELINE_INTEGRITY_PATH,
    "runtime_metrics": RUNTIME_METRICS_PATH,
}


def load_json(path: pathlib.Path) -> Dict[str, object]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: pathlib.Path, payload: Dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def run_git(args: List[str]) -> Tuple[int, str]:
    proc = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)
    return proc.returncode, proc.stdout.strip()


def detect_commit_id() -> str:
    env_sha = os.environ.get("GITHUB_SHA", "").strip()
    if env_sha:
        return env_sha
    rc, out = run_git(["git", "rev-parse", "--verify", "HEAD"])
    return out if rc == 0 else ""


def iso_utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_metric_results(thresholds_payload: Dict[str, object]) -> Tuple[List[Dict[str, object]], List[str]]:
    rows: List[Dict[str, object]] = []
    errors: List[str] = []
    results = thresholds_payload.get("results", [])
    if not isinstance(results, list):
        return rows, ["thresholds payload must contain array field 'results'"]

    for item in results:
        if not isinstance(item, dict):
            errors.append("threshold result entry must be an object")
            continue
        metric = item.get("metric")
        status = str(item.get("status", "")).lower()
        if not isinstance(metric, str) or not metric:
            errors.append("threshold result is missing metric name")
            continue
        if status not in {"pass", "fail"}:
            errors.append(f"threshold result for metric '{metric}' is missing pass/fail status")
            continue
        rows.append(
            {
                "metric": metric,
                "scope": item.get("scope", "aggregate"),
                "scenario_id": item.get("scenario_id"),
                "status": status,
                "observed": item.get("observed"),
                "expected": item.get("expected"),
                "comparator": item.get("comparator"),
            }
        )
    return rows, errors


def classify_dual_objective(metric_rows: List[Dict[str, object]]) -> Dict[str, object]:
    quality_rows = [row for row in metric_rows if not str(row.get("metric", "")).startswith("runtime_")]
    runtime_rows = [row for row in metric_rows if str(row.get("metric", "")).startswith("runtime_")]

    quality_pass = bool(quality_rows) and all(str(row.get("status")) == "pass" for row in quality_rows)
    runtime_pass = bool(runtime_rows) and all(str(row.get("status")) == "pass" for row in runtime_rows)
    overall_pass = quality_pass and runtime_pass

    return {
        "status": "pass" if overall_pass else "fail",
        "quality_determinism": {
            "status": "pass" if quality_pass else "fail",
            "evaluated_metrics": quality_rows,
        },
        "runtime_performance": {
            "status": "pass" if runtime_pass else "fail",
            "evaluated_metrics": runtime_rows,
        },
    }


def collect_scenario_metadata(metrics_payload: Dict[str, object]) -> Dict[str, object]:
    runs = metrics_payload.get("scenario_runs", [])
    scenarios: List[Dict[str, object]] = []
    seeds: Dict[str, object] = {}
    if isinstance(runs, list):
        for run in runs:
            if not isinstance(run, dict):
                continue
            scenario_id = run.get("scenario_id")
            if not isinstance(scenario_id, str) or not scenario_id:
                continue
            seed = run.get("seed")
            scenarios.append(
                {
                    "scenario_id": scenario_id,
                    "seed": seed,
                    "metrics_available": sorted(run.get("metrics", {}).keys()) if isinstance(run.get("metrics"), dict) else [],
                }
            )
            if seed is not None:
                seeds[scenario_id] = seed
    return {
        "scenario_set_id": metrics_payload.get("scenario_set_id"),
        "phase": metrics_payload.get("phase"),
        "scenarios": scenarios,
        "seeds": seeds,
    }


def parse_adr_index_ids(text: str) -> List[str]:
    out: List[str] = []
    for line in text.splitlines():
        match = re.match(r"\|\s*(ADR-\d+)\s*\|", line)
        if match:
            out.append(match.group(1))
    return sorted(set(out))


def collect_touched_adr_ids() -> Tuple[List[str], List[str]]:
    warnings: List[str] = []
    if not ADR_INDEX_PATH.exists():
        warnings.append(f"ADR index not found at {ADR_INDEX_PATH}")
        return [], warnings

    adr_index_text = ADR_INDEX_PATH.read_text(encoding="utf-8")
    known_adr_ids = set(parse_adr_index_ids(adr_index_text))
    if not known_adr_ids:
        warnings.append("No ADR IDs found in ADR index table")
        return [], warnings

    days_window = os.environ.get("CYCLE_WINDOW_DAYS", "84").strip()
    since_expr = f"--since={days_window} days ago"
    rc, logs = run_git(["git", "log", "--name-only", "--pretty=format:%H%n%s%n%b", since_expr])
    if rc != 0:
        warnings.append("Unable to derive ADR changes from git history")
        return [], warnings

    touched: set = set()
    for adr_id in known_adr_ids:
        if re.search(rf"\b{re.escape(adr_id)}\b", logs):
            touched.add(adr_id)

    explicit_ids = os.environ.get("CYCLE_ADR_IDS", "").strip()
    if explicit_ids:
        for token in explicit_ids.split(","):
            token_clean = token.strip()
            if token_clean:
                touched.add(token_clean)

    unknown_explicit = sorted([adr for adr in touched if adr not in known_adr_ids])
    if unknown_explicit:
        warnings.append(
            "Explicit ADR IDs are not in docs/governance/adr-index.md: " + ", ".join(unknown_explicit)
        )

    known_touched = sorted([adr for adr in touched if adr in known_adr_ids])
    return known_touched, warnings


def adr_links(adr_ids: List[str]) -> List[Dict[str, str]]:
    return [
        {
            "adr_id": adr_id,
            "index_ref": str(ADR_INDEX_PATH),
        }
        for adr_id in adr_ids
    ]


def maybe_json(path: pathlib.Path) -> Optional[Dict[str, object]]:
    if not path.exists():
        return None
    return load_json(path)


def build_evidence_index(source_payloads: Dict[str, pathlib.Path], output_paths: List[pathlib.Path]) -> Dict[str, object]:
    source_entries: List[Dict[str, object]] = []
    for label, path in source_payloads.items():
        if not path.exists():
            continue
        source_entries.append(
            {
                "label": label,
                "path": str(path),
                "sha256": sha256_file(path),
            }
        )

    output_entries: List[Dict[str, object]] = []
    for path in output_paths:
        if not path.exists():
            continue
        output_entries.append(
            {
                "path": str(path),
                "sha256": sha256_file(path),
            }
        )

    return {
        "generated_at_utc": iso_utc_now(),
        "source_artifacts": source_entries,
        "bundle_artifacts": output_entries,
    }


def markdown_summary(summary: Dict[str, object]) -> str:
    dual = summary.get("dual_objective", {})
    quality = dual.get("quality_determinism", {}) if isinstance(dual, dict) else {}
    runtime = dual.get("runtime_performance", {}) if isinstance(dual, dict) else {}
    det = summary.get("determinism_evidence", {})
    perf = summary.get("performance_evidence", {})
    baseline = summary.get("baseline_delta", {})
    scenario = summary.get("scenario_metadata", {})
    adrs = summary.get("adr_links", [])
    warnings = summary.get("warnings", [])
    links = summary.get("artifact_links", [])

    lines = [
        "# Cycle Closeout Evidence Summary",
        "",
        f"- cycle_id: `{summary.get('cycle_id')}`",
        f"- generated_at_utc: `{summary.get('generated_at_utc')}`",
        f"- commit_id: `{summary.get('commit_id')}`",
        f"- policy_phase: `{summary.get('policy_phase')}`",
        f"- status: `{summary.get('status')}`",
        "",
        "## Dual Objective Verdict",
        "",
        f"- quality_determinism: `{quality.get('status')}`",
        f"- runtime_performance: `{runtime.get('status')}`",
        "",
        "## Scenario Metadata",
        "",
        f"- scenario_set_id: `{scenario.get('scenario_set_id')}`",
        f"- phase: `{scenario.get('phase')}`",
        f"- scenario_count: `{len(scenario.get('scenarios', [])) if isinstance(scenario.get('scenarios'), list) else 0}`",
        "",
        "## Determinism and Performance Evidence",
        "",
        f"- D1_ReplayHashMatchRate: `{det.get('D1_ReplayHashMatchRate')}`",
        f"- D2_EventStreamMatchRate: `{det.get('D2_EventStreamMatchRate')}`",
        f"- runtime_median_ms: `{perf.get('runtime_median_ms')}`",
        f"- runtime_p95_ms: `{perf.get('runtime_p95_ms')}`",
        "",
        "## Baseline Delta",
        "",
        f"- status: `{baseline.get('status')}`",
        f"- baseline_id: `{baseline.get('baseline_id')}`",
        f"- scenario_delta_count: `{len(baseline.get('scenario_deltas', [])) if isinstance(baseline.get('scenario_deltas'), list) else 0}`",
        "",
        "## ADR IDs Touched",
        "",
    ]
    if isinstance(adrs, list) and adrs:
        for item in adrs:
            if isinstance(item, dict):
                lines.append(f"- `{item.get('adr_id')}`")
    else:
        lines.append("- none-detected")

    lines.extend(["", "## Artifact Links", ""])
    if isinstance(links, list) and links:
        for link in links:
            lines.append(f"- `{link}`")
    else:
        lines.append("- none-provided")

    if isinstance(warnings, list) and warnings:
        lines.extend(["", "## Warnings", ""])
        for warning in warnings:
            lines.append(f"- {warning}")
    return "\n".join(lines) + "\n"


def main() -> int:
    missing_inputs = [label for label, path in REQUIRED_INPUTS.items() if not path.exists()]
    if missing_inputs:
        raise SystemExit("Missing required cycle evidence inputs: " + ", ".join(missing_inputs))

    lane_performance = load_json(LANE_PERFORMANCE_PATH)
    thresholds = load_json(THRESHOLDS_PATH)
    baseline_delta = load_json(BASELINE_DELTA_PATH)
    baseline_integrity = load_json(BASELINE_INTEGRITY_PATH)
    runtime_metrics = load_json(RUNTIME_METRICS_PATH)
    risk_signals = maybe_json(RISK_SIGNALS_PATH) or {"signals": []}
    env_payload = maybe_json(ENV_FINGERPRINT_PATH) or {}

    metric_rows, metric_errors = parse_metric_results(thresholds)
    dual = classify_dual_objective(metric_rows)

    determinism = {
        "D1_ReplayHashMatchRate": runtime_metrics.get("aggregate_metrics", {}).get("D1_ReplayHashMatchRate")
        if isinstance(runtime_metrics.get("aggregate_metrics"), dict)
        else None,
        "D2_EventStreamMatchRate": runtime_metrics.get("aggregate_metrics", {}).get("D2_EventStreamMatchRate")
        if isinstance(runtime_metrics.get("aggregate_metrics"), dict)
        else None,
        "environment_fingerprint": env_payload.get("fingerprint", runtime_metrics.get("environment_fingerprint")),
    }

    performance = {
        "runtime_median_ms": runtime_metrics.get("aggregate_metrics", {}).get("runtime_median_ms")
        if isinstance(runtime_metrics.get("aggregate_metrics"), dict)
        else None,
        "runtime_p95_ms": runtime_metrics.get("aggregate_metrics", {}).get("runtime_p95_ms")
        if isinstance(runtime_metrics.get("aggregate_metrics"), dict)
        else None,
        "risk_signals": risk_signals.get("signals", []),
    }

    touched_adr_ids, adr_warnings = collect_touched_adr_ids()
    warnings: List[str] = []
    warnings.extend(metric_errors)
    warnings.extend(adr_warnings)

    artifact_links = runtime_metrics.get("artifact_links", [])
    if not isinstance(artifact_links, list):
        artifact_links = []
        warnings.append("runtime metrics payload has invalid 'artifact_links' field; expected list")

    cycle_id = os.environ.get("CYCLE_ID", "").strip() or f"cycle-auto-{dt.date.today().isoformat()}"
    policy_phase = os.environ.get("POLICY_PHASE", "").strip() or str(runtime_metrics.get("phase", "unknown"))
    commit_id = detect_commit_id()

    baseline_integrity_status = str(baseline_integrity.get("status", "")).lower()
    lane_status = str(lane_performance.get("status", "")).lower()
    required_checks_pass = lane_status == "pass" and baseline_integrity_status == "pass"
    status = "pass" if dual.get("status") == "pass" and required_checks_pass else "fail"

    summary = {
        "schema_version": "cycle-evidence-v1",
        "cycle_id": cycle_id,
        "generated_at_utc": iso_utc_now(),
        "commit_id": commit_id,
        "policy_phase": policy_phase,
        "status": status,
        "dual_objective": dual,
        "scenario_metadata": collect_scenario_metadata(runtime_metrics),
        "metric_pass_fail": metric_rows,
        "baseline_delta": baseline_delta,
        "baseline_integrity": baseline_integrity,
        "determinism_evidence": determinism,
        "performance_evidence": performance,
        "artifact_links": artifact_links,
        "adr_links": adr_links(touched_adr_ids),
        "source_artifacts": {
            "lane_performance": str(LANE_PERFORMANCE_PATH),
            "thresholds": str(THRESHOLDS_PATH),
            "baseline_delta": str(BASELINE_DELTA_PATH),
            "baseline_integrity": str(BASELINE_INTEGRITY_PATH),
            "runtime_metrics": str(RUNTIME_METRICS_PATH),
            "risk_signals": str(RISK_SIGNALS_PATH),
            "env_fingerprint": str(ENV_FINGERPRINT_PATH),
            "adr_index": str(ADR_INDEX_PATH),
        },
        "warnings": warnings,
    }

    BUNDLE_DIR.mkdir(parents=True, exist_ok=True)
    write_json(SUMMARY_JSON_PATH, summary)
    SUMMARY_MD_PATH.write_text(markdown_summary(summary), encoding="utf-8")

    evidence_index = build_evidence_index(
        source_payloads={
            "lane_performance": LANE_PERFORMANCE_PATH,
            "thresholds": THRESHOLDS_PATH,
            "baseline_delta": BASELINE_DELTA_PATH,
            "baseline_integrity": BASELINE_INTEGRITY_PATH,
            "runtime_metrics": RUNTIME_METRICS_PATH,
            "risk_signals": RISK_SIGNALS_PATH,
            "env_fingerprint": ENV_FINGERPRINT_PATH,
            "adr_index": ADR_INDEX_PATH,
        },
        output_paths=[SUMMARY_JSON_PATH, SUMMARY_MD_PATH],
    )
    write_json(INDEX_JSON_PATH, evidence_index)

    if status != "pass":
        print("Cycle evidence bundle failed required checks. See artifacts/cycle-evidence/cycle-evidence-summary.json.")
        return 1

    print("Generated cycle evidence bundle in artifacts/cycle-evidence/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
