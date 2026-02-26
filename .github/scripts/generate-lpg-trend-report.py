#!/usr/bin/env python3
import datetime as dt
import json
import os
import pathlib
from typing import Dict, List, Tuple


ARTIFACT_DIR = pathlib.Path("artifacts/policy")
LANE_PERF_PATH = ARTIFACT_DIR / "lane-performance.json"
THRESHOLDS_PATH = ARTIFACT_DIR / "lane-performance-thresholds.json"
RISK_PATH = ARTIFACT_DIR / "lane-performance-risk-signals.json"
OUTPUT_JSON = ARTIFACT_DIR / "lpg-trend-report.json"
OUTPUT_MD = ARTIFACT_DIR / "lpg-trend-report.md"


def load_json(path: pathlib.Path) -> Dict[str, object]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def maybe_history(path: pathlib.Path) -> List[Dict[str, object]]:
    if not path.exists():
        return []
    try:
        payload = load_json(path)
    except Exception:
        return []
    entries = payload.get("entries", [])
    if isinstance(entries, list):
        return [entry for entry in entries if isinstance(entry, dict)]
    return []


def compute_streak(entries: List[Dict[str, object]], current_status: str) -> Tuple[int, int]:
    pass_streak = 1 if current_status == "pass" else 0
    fail_streak = 1 if current_status == "fail" else 0
    for entry in reversed(entries):
        status = str(entry.get("status", "")).lower()
        if status == "pass" and pass_streak > 0:
            pass_streak += 1
        else:
            pass_streak = 0 if pass_streak == 0 else pass_streak

        if status == "fail" and fail_streak > 0:
            fail_streak += 1
        else:
            fail_streak = 0 if fail_streak == 0 else fail_streak

        if pass_streak == 0 and fail_streak == 0:
            break
        if pass_streak > 0 and status != "pass":
            break
        if fail_streak > 0 and status != "fail":
            break
    return pass_streak, fail_streak


def extract_runtime_metrics(thresholds_payload: Dict[str, object]) -> Dict[str, object]:
    metrics: Dict[str, object] = {
        "runtime_median_ms": None,
        "runtime_p95_ms": None,
    }
    for item in thresholds_payload.get("results", []):
        if not isinstance(item, dict):
            continue
        metric = item.get("metric")
        if metric in metrics:
            metrics[metric] = {
                "observed": item.get("observed"),
                "expected": item.get("expected"),
                "status": item.get("status"),
            }
    return metrics


def main() -> int:
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)

    if not LANE_PERF_PATH.exists():
        raise SystemExit(f"Missing required artifact: {LANE_PERF_PATH}")
    if not THRESHOLDS_PATH.exists():
        raise SystemExit(f"Missing required artifact: {THRESHOLDS_PATH}")

    lane_perf = load_json(LANE_PERF_PATH)
    thresholds = load_json(THRESHOLDS_PATH)
    risk = load_json(RISK_PATH) if RISK_PATH.exists() else {"signals": []}

    history_path = pathlib.Path(os.environ.get("LPG_TREND_HISTORY_PATH", ""))
    history_entries: List[Dict[str, object]] = []
    if str(history_path):
        history_entries = maybe_history(history_path)

    current_status = str(lane_perf.get("status", "unknown")).lower()
    pass_streak, fail_streak = compute_streak(history_entries, current_status)
    runtime_metrics = extract_runtime_metrics(thresholds)

    report = {
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "lane": "performance",
        "status": current_status,
        "phase": lane_perf.get("phase"),
        "scenario_set_id": lane_perf.get("scenario_set_id"),
        "runtime_metrics": runtime_metrics,
        "streaks": {
            "pass": pass_streak,
            "fail": fail_streak,
        },
        "risk_signals": risk.get("signals", []),
        "history_source": str(history_path) if str(history_path) else None,
        "history_entries_used": len(history_entries),
    }

    OUTPUT_JSON.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    md = [
        "# LPG Trend Report",
        "",
        f"- generated_at_utc: `{report['generated_at_utc']}`",
        f"- status: `{report['status']}`",
        f"- phase: `{report['phase']}`",
        f"- scenario_set_id: `{report['scenario_set_id']}`",
        f"- pass_streak: `{report['streaks']['pass']}`",
        f"- fail_streak: `{report['streaks']['fail']}`",
        "",
        "## Runtime Metrics",
        "",
        f"- runtime_median_ms: `{report['runtime_metrics']['runtime_median_ms']}`",
        f"- runtime_p95_ms: `{report['runtime_metrics']['runtime_p95_ms']}`",
        "",
        "## Risk Signals",
        "",
        f"- signals: `{report['risk_signals']}`",
    ]
    OUTPUT_MD.write_text("\n".join(md) + "\n", encoding="utf-8")

    print(f"Generated {OUTPUT_JSON} and {OUTPUT_MD}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
