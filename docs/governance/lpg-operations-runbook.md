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
- current minimal harness entrypoint is intentionally strict-fail until real benchmark backend wiring is complete.

### 2) Trigger Non-Default Proof Run

Run `policy-verdict` from GitHub Actions UI:

- workflow: `policy-verdict`,
- input: `policy_phase=phase-2` (or other non-default phase).

Expected results:

- `lane-runtime-benchmark` succeeds using real harness output,
- `lane-performance` consumes `artifacts/perf/lpg-metrics.json`,
- `policy-verdict` publishes `artifacts/policy/final-verdict.json` with `status=pass`.

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
