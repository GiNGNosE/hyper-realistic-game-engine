#!/usr/bin/env python3
import json
import pathlib
import sys
from typing import Dict, List


ARTIFACT_DIR = pathlib.Path("artifacts/policy")
INPUT_FILES = {
    "lane_performance": ARTIFACT_DIR / "lane-performance.json",
    "thresholds": ARTIFACT_DIR / "lane-performance-thresholds.json",
    "risk_signals": ARTIFACT_DIR / "lane-performance-risk-signals.json",
    "trend_report": ARTIFACT_DIR / "lpg-trend-report.json",
}
OUTPUT_PATH = ARTIFACT_DIR / "lpg-artifact-review.json"


def load_json(path: pathlib.Path) -> Dict[str, object]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def main() -> int:
    missing = [name for name, path in INPUT_FILES.items() if not path.exists()]
    if missing:
        print(f"Missing required artifact inputs: {', '.join(missing)}")
        return 1

    lane = load_json(INPUT_FILES["lane_performance"])
    thresholds = load_json(INPUT_FILES["thresholds"])
    risk = load_json(INPUT_FILES["risk_signals"])
    trend = load_json(INPUT_FILES["trend_report"])

    findings: List[Dict[str, object]] = []
    actions: List[str] = []

    if str(lane.get("status", "")).lower() != "pass":
        findings.append(
            {
                "severity": "high",
                "type": "lane-failure",
                "message": "Lane performance did not pass",
                "evidence": lane.get("errors", []),
            }
        )
        actions.append("Block promotion and resolve lane-performance errors before next run.")

    failing_thresholds = [
        item
        for item in thresholds.get("results", [])
        if isinstance(item, dict) and str(item.get("status", "")).lower() == "fail"
    ]
    if failing_thresholds:
        findings.append(
            {
                "severity": "high",
                "type": "threshold-failure",
                "message": "One or more LPG thresholds failed",
                "evidence": failing_thresholds,
            }
        )
        actions.append("Run focused profiling or quality correction against failing metrics.")

    risk_signals = risk.get("signals", [])
    red_signals = [
        sig
        for sig in risk_signals
        if isinstance(sig, dict)
        and str(sig.get("severity", "")).lower() == "red"
        and bool(sig.get("trigger_observed"))
    ]
    if red_signals:
        findings.append(
            {
                "severity": "critical",
                "type": "red-risk-signal",
                "message": "Red risk signal observed in LPG risk output",
                "evidence": red_signals,
            }
        )
        actions.append("Enter correction mode and freeze non-mitigation scope in impacted area.")

    pass_streak = int(trend.get("streaks", {}).get("pass", 0) or 0)
    fail_streak = int(trend.get("streaks", {}).get("fail", 0) or 0)
    if fail_streak >= 2:
        findings.append(
            {
                "severity": "high",
                "type": "fail-streak",
                "message": f"Consecutive failure streak detected: {fail_streak}",
            }
        )
        actions.append("Escalate to weekly governance checkpoint and create corrective ADR if unresolved.")
    elif pass_streak >= 4:
        actions.append("Sustained pass streak detected; consider tightening next ladder checkpoint.")

    review = {
        "status": "pass" if not findings else "fail",
        "summary": {
            "phase": lane.get("phase"),
            "scenario_set_id": lane.get("scenario_set_id"),
            "lane_status": lane.get("status"),
            "pass_streak": pass_streak,
            "fail_streak": fail_streak,
        },
        "findings": findings,
        "recommended_actions": actions,
    }

    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(review, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
