# Policy Verdict Contract

This document defines the automated review board and merge authority contract.

## Final Authority

- CI job `policy-verdict` is the primary merge gate for lane and proof enforcement.
- Independent status check `reviewer-agent` is required for change-risk review.
- Independent status check `agent-delivery` is required to enforce agent ownership and submission metadata.
- Independent status check `agent-task-board` is required to enforce single-source task-board integrity.
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
- CI runtime benchmark production must use a direct harness command (`RUNTIME_HARNESS_CMD`); fixture/bootstrap fallback is forbidden in CI,
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

### Independent Reviewer-Agent Gate

- CI job `reviewer-agent` performs deterministic risk checks on pull requests.
- `reviewer-agent` emits `artifacts/policy/reviewer-agent-verdict.json`.
- `reviewer-agent` must pass as a required status check alongside `policy-verdict`.

### Independent Agent-Delivery Gate

- CI job `agent-delivery` validates agent ownership metadata for pull requests.
- `agent-delivery` emits `artifacts/policy/agent-delivery-validation.json`.
- `agent-delivery` must pass as a required status check alongside `policy-verdict`, `reviewer-agent`, and `agent-task-board`.
- `agent-delivery` requires `TaskBoardVersion`, `TaskID`, and `OwnerAgent` metadata and verifies mapping against `docs/governance/agent-task-board.md`.

### Independent Agent-Task-Board Gate

- CI job `agent-task-board` validates `docs/governance/agent-task-board.md` schema and hash integrity.
- `agent-task-board` emits `artifacts/policy/agent-task-board-validation.json`.
- Any board schema/hash mismatch is merge-blocking.

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
- `artifacts/policy/waiver-validation.json`
- `artifacts/policy/required-rules.json`
- `artifacts/policy/rule-read-receipt.json`
- `artifacts/policy/rule-read-receipt-validation.json`
- `artifacts/policy/rule-coverage-validation.json`
- `artifacts/policy/ambiguity-triggers.json`
- `artifacts/policy/clarification-validation.json`
- `artifacts/policy/proof-integrity-validation.json`
- `artifacts/policy/final-verdict.json`
- `artifacts/policy/reviewer-agent-verdict.json`
- `artifacts/policy/agent-delivery-validation.json`
- `artifacts/policy/agent-task-board-validation.json`

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
- deterministic ambiguity trigger generation and clarification requirements,
- integrity binding between proof artifacts and CI event context.

`missing_target_scope` trigger activation is event-scoped:

- active for `pull_request` and `push`,
- inactive for `workflow_dispatch` and `schedule`.

This is a behavioral refinement of trigger conditions; it does not remove required artifact fields.

Promotion must fail if any proof gate fails.

`policy-verdict` also includes a mandatory `lane-branch-governance` lane that enforces repository branch strategy policy for pull requests.

### Merge-Blocking Failure Conditions

- Missing `rule-read-receipt.json`.
- Receipt identity mismatch (`commit_id`, `pr_number`, `phase`, or changed paths).
- Rule inventory hash mismatch with CI-computed `.mdc` hash.
- Missing applicable rules in `applied_rules`.
- Ambiguity triggers detected without a valid `clarification-log.json`.
- Clarification entries missing `user_response` or `resolved_decision`.
- Branch naming or base-target policy violation in `lane-branch-governance`.
