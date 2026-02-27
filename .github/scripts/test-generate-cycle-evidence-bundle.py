#!/usr/bin/env python3
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT_PATH = pathlib.Path(__file__).with_name("generate-cycle-evidence-bundle.py").resolve()


def write_json(path: pathlib.Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


class GenerateCycleEvidenceBundleTest(unittest.TestCase):
    def _run_script(self, cwd: pathlib.Path) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT_PATH)],
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )

    def _seed_required_inputs(self, root: pathlib.Path) -> None:
        write_json(
            root / "artifacts/policy/lane-performance.json",
            {
                "status": "pass",
                "phase": "pre-phase-0",
            },
        )
        write_json(
            root / "artifacts/policy/lane-performance-thresholds.json",
            {
                "results": [
                    {
                        "metric": "D1_ReplayHashMatchRate",
                        "scope": "aggregate",
                        "status": "pass",
                        "observed": 100.0,
                        "expected": 100.0,
                        "comparator": "eq",
                    },
                    {
                        "metric": "runtime_median_ms",
                        "scope": "aggregate",
                        "status": "pass",
                        "observed": 15.0,
                        "expected": 20.0,
                        "comparator": "lte",
                    },
                    {
                        "metric": "runtime_p95_ms",
                        "scope": "aggregate",
                        "status": "pass",
                        "observed": 22.0,
                        "expected": 28.0,
                        "comparator": "lte",
                    },
                ]
            },
        )
        write_json(
            root / "artifacts/policy/baseline-delta.json",
            {
                "status": "pass",
                "baseline_id": "lpg-baseline-pre-phase-0-v1",
                "scenario_deltas": [],
            },
        )
        write_json(
            root / "artifacts/policy/baseline-integrity.json",
            {
                "status": "pass",
                "lineage_status": "pass",
                "integrity_status": "pass",
            },
        )
        write_json(
            root / "artifacts/perf/lpg-metrics.json",
            {
                "phase": "pre-phase-0",
                "scenario_set_id": "canonical-s1-s3",
                "aggregate_metrics": {
                    "D1_ReplayHashMatchRate": 100.0,
                    "runtime_median_ms": 15.0,
                    "runtime_p95_ms": 22.0,
                },
                "scenario_runs": [
                    {"scenario_id": "S1_LightTap", "seed": 101, "metrics": {}},
                    {"scenario_id": "S2_ChiselImpact", "seed": 202, "metrics": {}},
                    {"scenario_id": "S3_HeavyDrop", "seed": 303, "metrics": {}},
                ],
            },
        )
        (root / "docs/governance").mkdir(parents=True, exist_ok=True)
        (root / "docs/governance/adr-index.md").write_text(
            "\n".join(
                [
                    "# Architecture Decision Record (ADR) Index",
                    "",
                    "| ADR ID | Title | Status | Date | Supersedes | Affected Areas |",
                    "|---|---|---|---|---|---|",
                    "| ADR-0001 | Dual Objective Charter | accepted | 2026-02-26 | - | governance |",
                ]
            )
            + "\n",
            encoding="utf-8",
        )

    def test_generates_bundle_when_inputs_valid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self._seed_required_inputs(root)
            result = self._run_script(root)
            self.assertEqual(0, result.returncode, msg=result.stdout)

            summary_path = root / "artifacts/cycle-evidence/cycle-evidence-summary.json"
            index_path = root / "artifacts/cycle-evidence/evidence-index.json"
            md_path = root / "artifacts/cycle-evidence/cycle-evidence-summary.md"

            self.assertTrue(summary_path.exists())
            self.assertTrue(index_path.exists())
            self.assertTrue(md_path.exists())

            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            self.assertEqual("pass", summary.get("status"))
            self.assertEqual("cycle-evidence-v1", summary.get("schema_version"))
            self.assertIn("dual_objective", summary)

    def test_fails_when_required_input_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self._seed_required_inputs(root)
            (root / "artifacts/policy/baseline-integrity.json").unlink()

            result = self._run_script(root)
            self.assertNotEqual(0, result.returncode)
            self.assertIn("Missing required cycle evidence inputs", result.stdout)


if __name__ == "__main__":
    unittest.main()
