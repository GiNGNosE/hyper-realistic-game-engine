# LPG Runtime Harness Contract

This contract defines the minimum runtime benchmark harness behavior required by
`lane-runtime-benchmark` and consumed by Lane Performance Gate (LPG).

## Purpose

- provide one canonical runtime harness command for CI via `RUNTIME_HARNESS_CMD`,
- guarantee deterministic LPG input provenance,
- guarantee payload compatibility with `.github/scripts/run-performance-lane.py`.

## Canonical Entrypoint

Recommended in-repo entrypoint:

- `tools/runtime-harness/run-benchmark.sh`

Recommended `RUNTIME_HARNESS_CMD` shape:

- `./tools/runtime-harness/run-benchmark.sh --phase "${POLICY_PHASE}" --scenario-set "canonical-s1-s3" --output "artifacts/perf/lpg-metrics.json"`

Entrypoint rules:

- must be executable in `ubuntu-latest`,
- must not require interactive input,
- must fail fast on benchmark execution errors.

## Transitional Status (Current)

Current `tools/runtime-harness/run-benchmark.sh` is a strict-fail placeholder:

- supports `--phase`, `--scenario-set`, and `--output`,
- validates input contract shape,
- exits non-zero with a clear action message until real benchmark backend wiring
  is implemented.

This is intentional to avoid synthetic CI passes before a real runtime benchmark
engine is connected.

## Command Contract

The command provided by `RUNTIME_HARNESS_CMD` must:

1. Write output to `artifacts/perf/lpg-metrics.json` in CI.
2. Exit `0` only when the output file is complete and valid JSON.
3. Exit non-zero when benchmark execution fails or output generation fails.
4. Produce phase-aligned payload (`phase` must match `POLICY_PHASE`).

CI provenance constraints enforced by existing scripts:

- `.github/scripts/produce-runtime-benchmark-artifact.sh` requires a non-empty
  `RUNTIME_HARNESS_CMD` in CI.
- `.github/scripts/run-performance-lane.py` requires
  `LPG_METRICS_INPUT=artifacts/perf/lpg-metrics.json` in CI.

## Required Output Payload

The runtime harness output JSON must include these top-level fields:

- `phase` (string),
- `scenario_set_id` (string),
- `aggregate_metrics` (object),
- `scenario_runs` (array of objects),
- `environment_fingerprint` (object).

`scenario_runs[]` minimum structure:

- `scenario_id` (non-empty string),
- `metrics` (object),
- `seed` (numeric, strongly recommended for traceability).

`environment_fingerprint` required non-empty string fields:

- `compiler_toolchain_id`,
- `os_runtime_signature`,
- `cpu_class`,
- `gpu_class`,
- `key_build_flags`,
- `perf_profile_id`.

### Threshold Alignment Requirements

The harness does not define thresholds. LPG resolves thresholds from:

- `docs/pipeline/validation-metrics.md` (embedded `LPG_THRESHOLDS` contract).

The payload must still provide all metrics required by the active phase in
`aggregate_metrics` and, where scenario-scoped metrics are configured, in each
scenario `metrics` object.

Current phase gate expectations also require:

- payload `phase` equals `POLICY_PHASE`,
- payload `scenario_set_id` equals the active phase scenario set,
- all required scenario IDs in the active scenario set are present.

## Minimal Valid Payload Example

```json
{
  "phase": "pre-phase-0",
  "scenario_set_id": "canonical-s1-s3",
  "aggregate_metrics": {
    "D1_ReplayHashMatchRate": 100.0,
    "runtime_median_ms": 15.0,
    "runtime_p95_ms": 22.0
  },
  "scenario_runs": [
    {
      "scenario_id": "S1_LightTap",
      "seed": 101,
      "metrics": {
        "D1_ReplayHashMatchRate": 100.0,
        "runtime_median_ms": 13.0,
        "runtime_p95_ms": 19.0
      }
    }
  ],
  "environment_fingerprint": {
    "compiler_toolchain_id": "clang-18",
    "os_runtime_signature": "ubuntu-latest",
    "cpu_class": "x86_64-standard",
    "gpu_class": "n/a-or-runner-gpu-class",
    "key_build_flags": "-O2 -DNDEBUG",
    "perf_profile_id": "lpg-runtime-profile-v1"
  }
}
```

## Verification Checklist

### Local Contract Check

1. Run placeholder harness command directly:
   - `bash tools/runtime-harness/run-benchmark.sh --phase pre-phase-0 --scenario-set canonical-s1-s3 --output artifacts/perf/lpg-metrics.json`
2. Confirm explicit strict-fail behavior:
   - command exits non-zero,
   - output explains backend is not yet wired.
3. After backend wiring, rerun and then confirm:
   - `test -f artifacts/perf/lpg-metrics.json`
   - payload keys and types match this contract.
4. After backend wiring, run LPG lane locally against emitted artifact:
   - `POLICY_PHASE=<phase> LPG_METRICS_INPUT=artifacts/perf/lpg-metrics.json .github/scripts/run-performance-lane.sh`
5. After backend wiring, confirm pass/fail artifact exists:
   - `artifacts/policy/lane-performance.json`

### CI Contract Check

1. While placeholder is active, expect CI `lane-runtime-benchmark` to fail
   explicitly and non-silently.
2. Set repository Actions variable `RUNTIME_HARNESS_CMD` to real backend command
   once available.
3. Trigger `policy-verdict` with non-default phase (for example `phase-2`).
4. Verify:
   - `lane-runtime-benchmark` succeeds,
   - `lane-performance` consumes `artifacts/perf/lpg-metrics.json`,
   - `artifacts/policy/lane-performance.json` is generated,
   - `artifacts/policy/final-verdict.json` reflects lane results.

## Non-Goals

- This contract does not define benchmark internals.
- This contract does not redefine threshold values.
- This contract does not replace baseline promotion policy.
