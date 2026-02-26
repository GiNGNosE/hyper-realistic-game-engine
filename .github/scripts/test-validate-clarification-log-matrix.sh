#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FIXTURES_DIR="${REPO_ROOT}/.github/scripts/fixtures/clarification-validator"
OUTPUT_DIR="${REPO_ROOT}/artifacts/policy"

mkdir -p "${OUTPUT_DIR}"

python3 - "${REPO_ROOT}" "${FIXTURES_DIR}" "${OUTPUT_DIR}" <<'PY'
import json
import os
import pathlib
import subprocess
import sys
import tempfile
from typing import Dict, List

repo_root = pathlib.Path(sys.argv[1])
fixtures_dir = pathlib.Path(sys.argv[2])
output_dir = pathlib.Path(sys.argv[3])
validator = repo_root / ".github/scripts/validate-clarification-log.sh"
guardrail = repo_root / ".github/scripts/validate-clarification-event-gating.sh"

if not fixtures_dir.exists():
    raise SystemExit(f"Missing fixtures directory: {fixtures_dir}")

fixture_paths = sorted(fixtures_dir.glob("*.json"))
if not fixture_paths:
    raise SystemExit(f"No fixtures found in: {fixtures_dir}")

def load_json(path: pathlib.Path, *, strict: bool = True):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        if strict:
            raise
        return {}

def write_fixture_inputs(tmp_root: pathlib.Path, fixture: Dict[str, object]) -> None:
    inputs = fixture.get("inputs", {})
    if not isinstance(inputs, dict):
        raise ValueError("inputs must be an object")
    for rel_path in sorted(inputs):
        spec = inputs[rel_path]
        if not isinstance(spec, dict):
            raise ValueError(f"input spec for {rel_path} must be an object")
        target = tmp_root / rel_path
        target.parent.mkdir(parents=True, exist_ok=True)
        if "json" in spec:
            target.write_text(
                json.dumps(spec["json"], indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
        elif "raw" in spec:
            target.write_text(str(spec["raw"]), encoding="utf-8")
        else:
            raise ValueError(f"input spec for {rel_path} requires json or raw")

def write_artifacts_from_spec(tmp_root: pathlib.Path, spec_map: Dict[str, object]) -> None:
    for rel_path in sorted(spec_map):
        spec = spec_map[rel_path]
        if not isinstance(spec, dict):
            raise ValueError(f"input spec for {rel_path} must be an object")
        target = tmp_root / rel_path
        target.parent.mkdir(parents=True, exist_ok=True)
        if "json" in spec:
            target.write_text(
                json.dumps(spec["json"], indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
        elif "raw" in spec:
            target.write_text(str(spec["raw"]), encoding="utf-8")
        elif spec.get("delete") is True:
            target.unlink(missing_ok=True)
        else:
            raise ValueError(f"input spec for {rel_path} requires json, raw, or delete=true")

def trigger_types(triggers_artifact: Dict[str, object]) -> List[str]:
    raw = triggers_artifact.get("triggers", [])
    if not isinstance(raw, list):
        return []
    out = []
    for item in raw:
        if isinstance(item, dict):
            value = item.get("trigger_type", "")
            if isinstance(value, str) and value:
                out.append(value)
    return sorted(set(out))

results = []
for fixture_path in fixture_paths:
    fixture = load_json(fixture_path)
    scenario_id = str(fixture.get("scenario_id", "")).strip() or fixture_path.stem
    event_name = str(fixture.get("event_name", "")).strip() or "unknown"
    expect = fixture.get("expect", {})
    if not isinstance(expect, dict):
        raise SystemExit(f"Fixture {fixture_path} has non-object expect")

    with tempfile.TemporaryDirectory(prefix="clarification-matrix-") as tmp:
        tmp_root = pathlib.Path(tmp)
        write_fixture_inputs(tmp_root, fixture)
        proc = subprocess.run(
            [str(validator)],
            cwd=tmp_root,
            env={**os.environ, "GITHUB_EVENT_NAME": event_name},
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        post_validator_overrides = fixture.get("post_validator_overrides", {})
        if post_validator_overrides:
            if not isinstance(post_validator_overrides, dict):
                raise SystemExit(f"Fixture {fixture_path} has non-object post_validator_overrides")
            write_artifacts_from_spec(tmp_root, post_validator_overrides)

        validation_path = tmp_root / "artifacts/policy/clarification-validation.json"
        triggers_path = tmp_root / "artifacts/policy/ambiguity-triggers.json"
        guardrail_path = tmp_root / "artifacts/policy/clarification-event-gating-guardrail.json"

        validation = load_json(validation_path, strict=False) if validation_path.exists() else {}
        triggers = load_json(triggers_path, strict=False) if triggers_path.exists() else {}
        observed_trigger_types = trigger_types(triggers)
        guardrail_proc = subprocess.run(
            [str(guardrail)],
            cwd=tmp_root,
            env={
                **os.environ,
                "MATRIX_SCENARIO_ID": scenario_id,
                "MATRIX_FIXTURE_PATH": str(fixture_path.relative_to(repo_root)),
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        guardrail_payload = load_json(guardrail_path, strict=False) if guardrail_path.exists() else {}

        checks: List[str] = []
        failures: List[str] = []
        expectation_diffs: List[Dict[str, object]] = []

        def check_equal(key: str, observed, expected) -> None:
            checks.append(key)
            if observed != expected:
                failures.append(f"{key}: expected {expected!r}, observed {observed!r}")
                expectation_diffs.append(
                    {
                        "check": key,
                        "expected": expected,
                        "observed": observed,
                    }
                )

        if "exit_code" in expect:
            check_equal("exit_code", proc.returncode, expect["exit_code"])
        if "validation_artifact_present" in expect:
            check_equal("validation_artifact_present", validation_path.exists(), expect["validation_artifact_present"])
        if "status" in expect:
            check_equal("status", validation.get("status", ""), expect["status"])
        if "required_clarification" in expect:
            check_equal(
                "required_clarification",
                bool(validation.get("required_clarification", False)),
                bool(expect["required_clarification"]),
            )
        if "target_scope_required" in expect:
            check_equal(
                "target_scope_required",
                bool(validation.get("target_scope_required", False)),
                bool(expect["target_scope_required"]),
            )
        if "input_artifact_error_count" in expect:
            check_equal(
                "input_artifact_error_count",
                int(validation.get("input_artifact_error_count", 0)),
                int(expect["input_artifact_error_count"]),
            )
        if "contains_errors" in expect:
            checks.append("contains_errors")
            observed_errors = [str(item) for item in validation.get("errors", []) if isinstance(item, str)]
            missing_error_snippets = []
            for required_substring in expect["contains_errors"]:
                if not any(required_substring in observed for observed in observed_errors):
                    missing_error_snippets.append(required_substring)
            if missing_error_snippets:
                failures.append(f"contains_errors: missing {missing_error_snippets}")
                expectation_diffs.append(
                    {
                        "check": "contains_errors",
                        "expected_contains": sorted(expect["contains_errors"]),
                        "observed": observed_errors,
                    }
                )
        if "guardrail_status" in expect:
            check_equal("guardrail_status", guardrail_payload.get("status", ""), expect["guardrail_status"])
        if "guardrail_contains_error_codes" in expect:
            checks.append("guardrail_contains_error_codes")
            observed_codes = sorted(
                {
                    err.get("code", "")
                    for err in guardrail_payload.get("scenario_errors", [])
                    if isinstance(err, dict) and isinstance(err.get("code", ""), str)
                }
            )
            expected_codes = set(expect["guardrail_contains_error_codes"])
            missing_codes = sorted(code for code in expected_codes if code not in observed_codes)
            if missing_codes:
                failures.append(f"guardrail_contains_error_codes: missing {missing_codes}")
                expectation_diffs.append(
                    {
                        "check": "guardrail_contains_error_codes",
                        "expected_contains": sorted(expected_codes),
                        "observed": observed_codes,
                    }
                )
        if "contains_trigger_types" in expect:
            checks.append("contains_trigger_types")
            expected = set(expect["contains_trigger_types"])
            missing = sorted(t for t in expected if t not in observed_trigger_types)
            if missing:
                failures.append(f"contains_trigger_types: missing {missing}")
                expectation_diffs.append(
                    {
                        "check": "contains_trigger_types",
                        "expected_contains": sorted(expected),
                        "observed": observed_trigger_types,
                    }
                )
        if "excludes_trigger_types" in expect:
            checks.append("excludes_trigger_types")
            expected = set(expect["excludes_trigger_types"])
            present = sorted(t for t in expected if t in observed_trigger_types)
            if present:
                failures.append(f"excludes_trigger_types: present {present}")
                expectation_diffs.append(
                    {
                        "check": "excludes_trigger_types",
                        "expected_excludes": sorted(expected),
                        "observed": observed_trigger_types,
                    }
                )

        results.append(
            {
                "scenario_id": scenario_id,
                "event_name": event_name,
                "fixture_path": str(fixture_path.relative_to(repo_root)),
                "status": "pass" if not failures else "fail",
                "checks": checks,
                "failures": failures,
                "expectation_diffs": expectation_diffs,
                "observed": {
                    "exit_code": proc.returncode,
                    "validation_artifact_present": validation_path.exists(),
                    "validation_status": validation.get("status", ""),
                    "target_scope_required": validation.get("target_scope_required", False),
                    "required_clarification": validation.get("required_clarification", False),
                    "input_artifact_error_count": int(validation.get("input_artifact_error_count", 0)),
                    "trigger_types": observed_trigger_types,
                    "guardrail_status": guardrail_payload.get("status", ""),
                    "guardrail_error_codes": sorted(
                        {
                            err.get("code", "")
                            for err in guardrail_payload.get("scenario_errors", [])
                            if isinstance(err, dict) and isinstance(err.get("code", ""), str)
                        }
                    ),
                },
                "stdout": proc.stdout.strip().splitlines(),
                "guardrail_stdout": guardrail_proc.stdout.strip().splitlines(),
            }
        )

results.sort(key=lambda item: item["scenario_id"])
failed = [item for item in results if item["status"] != "pass"]
payload = {
    "status": "pass" if not failed else "fail",
    "scenario_count": len(results),
    "failed_count": len(failed),
    "results": results,
}

output_json = output_dir / "clarification-validator-matrix.json"
output_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

summary_lines = [
    "# Clarification Validator Matrix Summary",
    "",
    f"- Overall status: `{payload['status']}`",
    f"- Scenarios: `{payload['scenario_count']}`",
    f"- Failed: `{payload['failed_count']}`",
    "",
    "| Scenario | Event | Result | Triggers |",
    "| --- | --- | --- | --- |",
]
for item in results:
    triggers_csv = ", ".join(item["observed"]["trigger_types"]) or "-"
    summary_lines.append(
        f"| `{item['scenario_id']}` | `{item['event_name']}` | `{item['status']}` | `{triggers_csv}` |"
    )
if failed:
    summary_lines.append("")
    summary_lines.append("## Failures")
    for item in failed:
        summary_lines.append(f"- `{item['scenario_id']}`: " + "; ".join(item["failures"]))
        for diff in item.get("expectation_diffs", []):
            summary_lines.append(f"  - `{diff['check']}` expected vs observed mismatch")

output_md = output_dir / "clarification-validator-matrix-summary.md"
output_md.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

if failed:
    raise SystemExit(1)
PY
