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

- `./tools/runtime-harness/run-benchmark.sh --phase "${POLICY_PHASE}" --scenario-set "canonical-s1-s3" --output "artifacts/perf/lpg-metrics.json" --backend-cmd "./build/runtime/lpg-runtime-benchmark --phase ${POLICY_PHASE} --scenario-set canonical-s1-s3 --output artifacts/perf/lpg-metrics.json"`

Current backend build step (local/CI command pre-step):

- `cmake -S runtime -B build/runtime -DCMAKE_BUILD_TYPE=Release && cmake --build build/runtime --config Release --target lpg-runtime-benchmark`

Entrypoint rules:

- must be executable in `ubuntu-latest`,
- must not require interactive input,
- must fail fast on benchmark execution errors.
- output parent directory creation is conditional: create directories only when
  `--output` has a non-empty parent path.

## Runtime Backend Bridge (Current)

Current `tools/runtime-harness/run-benchmark.sh` acts as a strict backend bridge:

- supports `--phase`, `--scenario-set`, `--output`, and `--backend-cmd`,
- resolves backend command from CLI `--backend-cmd` or environment variable
  `RUNTIME_BENCHMARK_BACKEND_CMD`,
- invokes the backend command with resolved harness context
  (`POLICY_PHASE`, `LPG_SCENARIO_SET_ID`, `LPG_RUNTIME_OUTPUT`),
- exits non-zero when backend execution fails,
- validates output schema, phase/scenario alignment, required scenario coverage,
  and active phase required metrics before returning success.
- currently supports only `pre-phase-0` for real metric emission; unsupported phases
  and scenario sets fail explicitly.
- when output directory creation fails, emits deterministic error messaging and
  a non-zero exit code.

## Command Contract

The command provided by `RUNTIME_HARNESS_CMD` must:

1. Write output to `artifacts/perf/lpg-metrics.json` in CI.
2. Exit `0` only when the output file is complete and valid JSON.
3. Exit non-zero when benchmark execution fails or output generation fails.
4. Produce phase-aligned payload (`phase` must match `POLICY_PHASE`).
5. Include complete phase-required metrics based on
   `docs/pipeline/validation-metrics.md`.

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

1. Run harness command with explicit backend command:
   - `bash tools/runtime-harness/run-benchmark.sh --phase pre-phase-0 --scenario-set canonical-s1-s3 --output artifacts/perf/lpg-metrics.json --backend-cmd "./build/runtime/lpg-runtime-benchmark --phase pre-phase-0 --scenario-set canonical-s1-s3 --output artifacts/perf/lpg-metrics.json"`
2. Confirm success behavior:
   - command exits `0`,
   - output confirms payload contract validation succeeded.
3. Confirm runtime artifact exists:
   - `test -f artifacts/perf/lpg-metrics.json`
4. Run LPG lane locally against emitted artifact:
   - `POLICY_PHASE=<phase> LPG_METRICS_INPUT=artifacts/perf/lpg-metrics.json .github/scripts/run-performance-lane.sh`
5. Confirm pass/fail artifact exists:
   - `artifacts/policy/lane-performance.json`

### CI Contract Check

1. Set repository Actions variable `RUNTIME_HARNESS_CMD` to include harness
   invocation and backend command arguments.
2. Trigger `policy-verdict` with `policy_phase=pre-phase-0`.
3. Verify bootstrap success:
   - `lane-runtime-benchmark` succeeds,
   - `lane-performance` consumes `artifacts/perf/lpg-metrics.json`,
   - `artifacts/policy/lane-performance.json` is generated,
   - `artifacts/policy/final-verdict.json` reflects lane results.
4. Trigger `policy-verdict` with non-default phase (for example `phase-2`) while
   backend scope remains `pre-phase-0`.
5. Verify explicit unsupported-phase failure:
   - `lane-runtime-benchmark` fails with unsupported phase message from backend,
   - failure is non-silent and does not produce synthetic pass artifacts.

## Non-Goals

- This contract does not define benchmark internals.
- This contract does not redefine threshold values.
- This contract does not replace baseline promotion policy.
