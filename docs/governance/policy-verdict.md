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
- deterministic replay checks,
- serialization integrity checks,
- required test classes by phase.

### Lane B: Performance and Fidelity

- performance regression checks,
- KPI conformance for `M*`, `V*`, `A*`, `D*`,
- baseline delta and lineage validation.

### Lane C: Branch Governance

- source branch taxonomy and naming validation,
- base branch target matrix validation,
- merge-route compliance for protected-trunk workflow.

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
- `artifacts/policy/lane-performance.json`
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
