# LPG Operations Runbook (Owner + Agent)

This runbook separates owner-only actions from agent-executable actions for operational LPG governance.

## Owner-Only Actions

### 1) Configure Runtime Harness Command

Set repository or organization variable:

- `RUNTIME_HARNESS_CMD`

Required behavior:

- command must emit `artifacts/perf/lpg-metrics.json`,
- command must return non-zero on benchmark failure,
- output JSON must match LPG schema contract.
- full command/payload contract is defined in `docs/governance/lpg-runtime-harness-contract.md`.
- recommended command includes explicit backend invocation, for example:
  - `./tools/runtime-harness/run-benchmark.sh --phase "${POLICY_PHASE}" --scenario-set "canonical-s1-s3" --output "artifacts/perf/lpg-metrics.json" --backend-cmd "./build/runtime/lpg-runtime-benchmark --phase ${POLICY_PHASE} --scenario-set canonical-s1-s3 --output artifacts/perf/lpg-metrics.json"`
- ensure benchmark backend binary is built before run:
  - `cmake -S runtime -B build/runtime -DCMAKE_BUILD_TYPE=Release && cmake --build build/runtime --config Release --target lpg-runtime-benchmark`
- bootstrap scope note: current backend supports `pre-phase-0` only and intentionally fails unsupported phases.

### 2) Trigger Non-Default Proof Run

Run `policy-verdict` from GitHub Actions UI:

- workflow: `policy-verdict`,
- input: `policy_phase=pre-phase-0` for bootstrap validation.

Expected results:

- `lane-runtime-benchmark` succeeds using real harness output,
- `lane-performance` consumes `artifacts/perf/lpg-metrics.json`,
- `policy-verdict` publishes `artifacts/policy/final-verdict.json` with `status=pass`.
- lane summary includes no phase/scenario mismatch errors.

Optional negative-path confirmation while scope remains bootstrap-only:

- run `policy-verdict` with `policy_phase=phase-2`,
- expect explicit `lane-runtime-benchmark` failure for unsupported phase,
- log the failure as expected until phase support is implemented.

### 3) Assign Weekly Governance Owners

Record named owners for:

- weekly trend review owner,
- escalation approver for `Red` triggers,
- cycle closeout sign-off owner.

## Agent-Executable Actions

- run `make lpg-review` after a completed CI run artifact pull,
- inspect `artifacts/policy/lpg-artifact-review.json`,
- propose corrective hardening updates when findings are present.

## Evidence Log Template

Maintain one entry per proof or weekly checkpoint:

- run_url:
- run_date_utc:
- policy_phase:
- final_verdict_status:
- pass_streak:
- fail_streak:
- runtime_median_ms_observed:
- runtime_p95_ms_observed:
- red_risk_triggered:
- owner_decision:
- follow_up_actions:
