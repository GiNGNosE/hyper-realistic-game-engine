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

## Checkpoint Evidence Log

### 2026-02-26 governance go-live checkpoint

- run_url: https://github.com/GiNGNosE/hyper-realistic-game-engine/actions/runs/22455190697
- run_date_utc: 2026-02-26T18:15:56Z
- policy_phase: pre-phase-0
- final_verdict_status: pass
- pass_streak: 1
- fail_streak: 0
- runtime_median_ms_observed: 15.0
- runtime_p95_ms_observed: 22.0
- red_risk_triggered: false
- owner_decision: checkpoint accepted; governance gate operational with enforced dispatch inputs.
- follow_up_actions:
  - keep RUNTIME_HARNESS_CMD pinned to canonical output path contract.
  - run weekly drift review with latest LPG trend artifacts.

### 2026-02-26 negative-path validation

- run_url: https://github.com/GiNGNosE/hyper-realistic-game-engine/actions/runs/22455257449
- run_date_utc: 2026-02-26T18:17:48Z
- policy_phase: phase-2
- final_verdict_status: fail (expected)
- pass_streak: 0
- fail_streak: 1 (expected-control failure)
- runtime_median_ms_observed: n/a (runtime lane failed before artifact emission)
- runtime_p95_ms_observed: n/a
- red_risk_triggered: false
- owner_decision: negative path behaved correctly; unsupported phase rejected explicitly by runtime backend.
- follow_up_actions:
  - retain explicit unsupported-phase failure until phase support is implemented and validated.

## Next Implementation Track

- phase-1 runtime expansion: extend `runtime/benchmark/main.cpp` and harness validation for `phase-1` required metrics from `docs/pipeline/validation-metrics.md` while preserving deterministic replay and runtime budgets.
