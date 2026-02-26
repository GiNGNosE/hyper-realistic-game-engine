# Policy Verdict Contract

This document defines the solo automated review board.

## Final Authority

- CI job `policy-verdict` is the sole promotion authority.
- No human reviewer is required for pass/fail decisions.
- Any failing mandatory gate blocks promotion.

## Required CI Lanes

### Lane A: Correctness and Determinism

- build/toolchain compliance,
- static analysis and sanitizers,
- pinned lint and style checks (C++, shell, workflow YAML, governance markdown),
- deterministic replay checks,
- serialization integrity checks,
- required test classes by phase.

### Lane B: Performance and Fidelity

- performance regression checks,
- KPI conformance for `M*`, `V*`, `A*`, `D*`,
- baseline delta and lineage validation.

Lane B must run through the Lane Performance Gate (LPG) contract:

- candidate metrics input in CI is downloaded runtime harness artifact `artifacts/perf/lpg-metrics.json`,
- CI runtime benchmark production must use a direct harness command (`RUNTIME_HARNESS_CMD`);
  fixture/bootstrap fallback is forbidden in CI,
- `RUNTIME_HARNESS_CMD` must be configured as repository/org CI variable and is mandatory for `lane-runtime-benchmark`,
- scenario set and seeds are loaded from threshold source metadata in `docs/pipeline/validation-metrics.md`,
- metric thresholds are resolved from that same source document (no duplicated constants in scripts),
- baseline integrity requires checksum and lineage validation against `baselines/metrics/lpg-index.json`,
- environment fingerprint is mandatory and includes compiler/toolchain, runtime signature, CPU/GPU class, and key flags,
- any required LPG check failure is merge-blocking.
- scheduled LPG drift checks run weekly and publish `lpg-trend-report` artifacts for governance review.
- operational handoff and ownership logging are maintained in `docs/governance/lpg-operations-runbook.md`.
- runtime harness command and payload contract are defined in `docs/governance/lpg-runtime-harness-contract.md`.

### Lane C: Branch Governance

- source branch taxonomy and naming validation,
- base branch target matrix validation,
- merge-route compliance for protected-trunk workflow.

### Lane D: PR Template Governance

- PR body must use one supported template marker:
  - `feature`,
  - `bugfix`,
  - `governance-docs`,
  - `baseline-promotion`.
- Required template sections must be present and non-empty.
- Required checklists must include explicit completion.
- Baseline-promotion PRs must include promotion intent metadata and lineage fields.

## Threshold Source of Truth

- Numeric thresholds must be loaded from `docs/pipeline/validation-metrics.md`.
- CI scripts must not define independent threshold constants unless generated from that source.

## Split Environment Model

- Replay lane runs in pinned deterministic environment.
- Performance lane runs on approved stable runner class.
- Both lanes emit environment fingerprints:
  - compiler/toolchain id,
  - OS/runtime signature,
  - CPU/GPU class,
  - key build flags.

## Required Machine-Readable Artifacts

- `artifacts/policy/lane-correctness.json`
- `artifacts/policy/lint-summary.json`
- `artifacts/policy/lint-tool-versions.json`
- `artifacts/policy/lint-cpp.json`
- `artifacts/policy/lint-shell.json`
- `artifacts/policy/lint-yaml.json`
- `artifacts/policy/lint-docs.json`
- `artifacts/policy/lane-performance.json`
- `artifacts/policy/lane-performance-env.json`
- `artifacts/policy/lane-performance-thresholds.json`
- `artifacts/policy/baseline-integrity.json`
- `artifacts/policy/baseline-delta.json`
- `artifacts/policy/lane-performance-risk-signals.json`
- `artifacts/policy/lane-branch-governance.json`
- `artifacts/policy/pr-template-validation.json`
- `artifacts/policy/waiver-validation.json`
- `artifacts/policy/required-rules.json`
- `artifacts/policy/rule-read-receipt.json`
- `artifacts/policy/rule-read-receipt-validation.json`
- `artifacts/policy/rule-coverage-validation.json`
- `artifacts/policy/ambiguity-triggers.json`
- `artifacts/policy/clarification-validation.json`
- `artifacts/policy/clarification-event-gating-guardrail.json`
- `artifacts/policy/proof-integrity-validation.json`
- `artifacts/policy/final-verdict.json`

Lint behavior and suppression lifecycle are defined in `docs/governance/linting-policy.md`.

## Waiver Enforcement

- Waivers are allowed from Phase 0 as break-glass exceptions.
- Expired waivers force `policy-verdict` failure.
- Waiver manifest fields are validated in CI:
  - scope, reason, owner, risk level, rollback plan, expiry.

## Hybrid Proof Enforcement Gates

`policy-verdict` includes a mandatory `proof-enforcement` lane that validates:

- deterministic applicable-rule resolution from phase and changed paths,
- rule receipt schema and per-rule evidence specificity,
- full applicable-rule coverage in declared and applied sets,
- deterministic ambiguity trigger generation and event-aware clarification requirements,
- integrity binding between proof artifacts and CI event context.

Proof-enforcement must evaluate clarification requirements with CI event context:

- `pull_request`, `push` -> target scope is required and `missing_target_scope` may activate.
- `workflow_dispatch`, `schedule` -> target scope is not required for trigger activation.
- Current `policy-verdict` workflow entry points are `pull_request`,
  `workflow_dispatch`, and `schedule`; `push` semantics apply when the validator
  runs under push-context lanes or harnesses.

`artifacts/policy/clarification-validation.json` remains mandatory proof output and must
include event-context fields (`event_name`, `target_scope_required`,
`required_clarification`, `errors`).

Promotion must fail if any proof gate fails.

Event-scoped clarification semantics for `missing_target_scope`:

| Event | Scope expectation | `missing_target_scope` |
| --- | --- | --- |
| `pull_request` | Scoped | Evaluated |
| `push` | Scoped | Evaluated |
| `workflow_dispatch` | Unscoped | Not evaluated |
| `schedule` | Unscoped | Not evaluated |

Compatibility note: this is a behavioral refinement and does not remove fields from
`artifacts/policy/ambiguity-triggers.json` or
`artifacts/policy/clarification-validation.json`.

`policy-verdict` also includes a mandatory `lane-branch-governance` lane that enforces
repository branch strategy policy for pull requests.

`policy-verdict` includes a mandatory `clarification-event-gating-guardrail` lane that
deterministically validates scoped/unscoped event behavior and fails on regressions.

### Merge-Blocking Failure Conditions

- Missing `rule-read-receipt.json`.
- Receipt identity mismatch (`commit_id`, `pr_number`, `phase`, or changed paths).
- Rule inventory hash mismatch with CI-computed `.mdc` hash.
- Missing applicable rules in `applied_rules`.
- Ambiguity triggers detected (after event-context evaluation) without a valid `clarification-log.json`.
- Clarification entries missing `user_response` or `resolved_decision`.
- Branch naming or base-target policy violation in `lane-branch-governance`.
- PR template marker/section/checklist validation failure in `lane-pr-template-governance`.

## Compatibility Note

Event-aware `missing_target_scope` activation is a behavioral refinement only. It does
not remove trigger types, required artifacts, or clarification validation fields.
